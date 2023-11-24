      module FASTMIEDIM
      integer,parameter :: Nx=400,Nn=200,Nk=400
      real,parameter :: nmin=0.8,nmax=100.0
      real,parameter :: kmin=1.E-3,kmax=100.0
      real,parameter :: xmin=1.E-6,xmax=50000.0
      real*4,dimension(0:Nx,0:Nn,0:Nk) :: lQsc,lQab
      end
      
************************************************************************
      subroutine FASTMIETAB
************************************************************************
      use FASTMIEDIM,ONLY: Nx,Nn,Nk,nmin,nmax,kmin,kmax,xmin,xmax,
     >                     lQsc,lQab
      use DATATYPE,ONLY: r2            ! from MIEX
      use MIE_ROUTINES,ONLY: SHEXQNN2  ! from MIEX
      implicit none
      integer :: i,j,k
      real :: nnn,kkk
      !------------ variables for data exchange with MIEX ---------
      complex(kind=r2) :: ri
      real(kind=r2)    :: xxx,Qext,Qsca,Qabs,Qbk,Qpr,albedo,g,mm1
      integer          :: ier,nang
      complex(kind=r2),dimension(2) :: SA1,SA2

      open(unit=12,file='fastmie.dat',form="unformatted",
     >     status='replace')
      write(12) Nx,Nn,Nk
      write(12) xmin,xmax
      write(12) nmin,nmax
      write(12) kmin,kmax
      nang = 3
      do i=0,Nx
        xxx = EXP(LOG(xmin)+i/REAL(Nx)*LOG(xmax/xmin))
!$omp parallel
!$omp& default(none)
!$omp& shared(nang,i,xxx,lQsc,lQab)
!$omp& private(j,k,nnn,kkk,ri,Qext,Qsca,Qabs,Qbk,Qpr)       
!$omp& private(albedo,g,ier,SA1,SA2)       
!$omp do schedule(dynamic,1)
        do j=0,Nn
          nnn = EXP(LOG(nmin)+j/REAL(Nn)*LOG(nmax/nmin))
          do k=0,Nk
            kkk = EXP(LOG(kmin)+k/REAL(Nk)*LOG(kmax/kmin))
            ri = DCMPLX(nnn,kkk)
            call SHEXQNN2(ri,xxx,Qext,Qsca,Qabs,Qbk,Qpr,
     >                    albedo,g,ier,SA1,SA2,.false.,nang)
            print*,i,j,k,ier,Qabs
            lQsc(i,j,k) = LOG(Qsca)
            lQab(i,j,k) = LOG(Qabs)
          enddo  
        enddo
!$omp end do      
!$omp end parallel        
      enddo
      write(12) lQsc,lQab
      close(12)
      end

************************************************************************
      subroutine FASTMIE(xval,nval,kval,Qsca,Qabs)
************************************************************************
      use FASTMIEDIM,ONLY: Nx,Nn,Nk,nmin,nmax,kmin,kmax,xmin,xmax,
     >                     lQsc,lQab
      implicit none
      real,intent(in) :: xval,nval,kval
      real,intent(out) :: Qabs,Qsca
      integer :: i,j,k,idum(3),Nx_read,Nn_read,Nk_read
      real :: a1,a2,b1,b2,c1,c2
      real :: xxx,kkk,nnn
      logical :: ex,match
      real :: n1_read,n2_read,k1_read,k2_read,x1_read,x2_read
      logical,save :: firstCall=.true.

      if (firstCall) then
        inquire(file='fastmie.dat',exist=ex)
 100    if (.not.ex) call FASTMIETAB
        open(unit=12,file='fastmie.dat',form="unformatted",status='old')
        read(12) Nx_read,Nn_read,Nk_read
        read(12) x1_read,x2_read
        read(12) n1_read,n2_read
        read(12) k1_read,k2_read
        match = (Nx_read==Nx).and.(Nn_read==Nn).and.(Nk_read==Nk).and.
     >          (x1_read==xmin).and.(x2_read==xmax).and. 
     >          (n1_read==nmin).and.(n2_read==nmax).and. 
     >          (k1_read==kmin).and.(k2_read==kmax)
        if (.not.match) then
          close(12)
          ex = .false.
          goto 100
        endif
        print*,"reading fastmie.dat ..."
        read(12) lQsc,lQab
        close(12)
        firstCall = .false.
        print*,"... done reading."
      endif
      
      xxx = LOG(xval/xmin)/LOG(xmax/xmin)*Nx
      nnn = LOG(nval/nmin)/LOG(nmax/nmin)*Nn
      kkk = LOG(kval/kmin)/LOG(kmax/kmin)*Nk
      i = INT(xxx)
      j = INT(nnn)
      k = INT(kkk)
      i = MAX(0,MIN(Nx-1,i))
      j = MAX(0,MIN(Nn-1,j))
      k = MAX(0,MIN(Nk-1,k))
      a1 = xxx-i
      a2 = 1.0-a1
      b1 = nnn-j
      b2 = 1.0-b1
      c1 = kkk-k
      c2 = 1.0-c1
      !print*,xxx,i,Nx,a1
      !print'(3(1pE12.4))',LOG(xmin)+i/REAL(Nx)*LOG(xmax/xmin),
     >!      LOG(xval),LOG(xmin)+(i+1)/REAL(Nx)*LOG(xmax/xmin)
      !print*,nnn,j,Nn,b1
      !print'(3(1pE12.4))',LOG(nmin)+j/REAL(Nn)*LOG(nmax/nmin),
     >!      LOG(nval),LOG(nmin)+(j+1)/REAL(Nn)*LOG(nmax/nmin)
      !print*,kkk,k,Nk,c1
      !print'(3(1pE12.4))',LOG(kmin)+k/REAL(Nk)*LOG(kmax/kmin),
     >!      LOG(kval),LOG(kmin)+(k+1)/REAL(Nk)*LOG(kmax/kmin)
      Qsca = EXP( lQsc(i  ,j,  k  )*a2*b2*c2
     >           +lQsc(i  ,j,  k+1)*a2*b2*c1
     >           +lQsc(i  ,j+1,k  )*a2*b1*c2
     >           +lQsc(i  ,j+1,k+1)*a2*b1*c1
     >           +lQsc(i+1,j  ,k  )*a1*b2*c2
     >           +lQsc(i+1,j  ,k+1)*a1*b2*c1
     >           +lQsc(i+1,j+1,k  )*a1*b1*c2
     >           +lQsc(i+1,j+1,k+1)*a1*b1*c1 )
      Qabs = EXP( lQab(i  ,j,  k  )*a2*b2*c2
     >           +lQab(i  ,j,  k+1)*a2*b2*c1
     >           +lQab(i  ,j+1,k  )*a2*b1*c2
     >           +lQab(i  ,j+1,k+1)*a2*b1*c1
     >           +lQab(i+1,j  ,k  )*a1*b2*c2
     >           +lQab(i+1,j  ,k+1)*a1*b2*c1
     >           +lQab(i+1,j+1,k  )*a1*b1*c2
     >           +lQab(i+1,j+1,k+1)*a1*b1*c1 )
      end
