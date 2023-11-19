***********************************************************************
      SUBROUTINE CALC_OPAC(nHges,eldust,T)
***********************************************************************
      use DUST_DATA,ONLY: NELEM,NDUST,elnam,eps0,bk,bar,amu,
     >                    muH,mass,mel,
     >                    dust_nam,dust_mass,dust_Vol,
     >                    dust_nel,dust_el,dust_nu
      use OPACITY,ONLY: NLAM,lam,NLIST,opind,duind,nn,kk
      implicit none
      integer,parameter :: qp=selected_real_kind(33,4931)
      real,intent(in) :: nHges,T
      real(kind=qp),intent(in) :: eldust(NDUST)
      real :: rhod1,rhod2,Vcon1,Vcon2,mass1,mass2,rhogr1,rhogr2,rho
      real :: neff,keff,Vs(NDUST)
      integer :: i,j,ilam
      
      rhod1 = 0.d0               ! dust mass density   [g/cm3]  
      Vcon1 = 0.d0               ! dust volume density [cm3/cm3]
      mass1 = 0.d0               ! dust mass density   [g/cm3]
      rhod2 = 0.d0               
      Vcon2 = 0.d0               ! same, but only opacity species
      mass2 = 0.d0
      do i=1,NDUST
        j = duind(i)
        if (eldust(i)<=0.Q0) cycle
        mass1 = mass1 + nHges*eldust(i)*dust_mass(i)
        rhod1 = rhod1 + nHges*eldust(i)*dust_mass(i)
        Vcon1 = Vcon1 + nHges*eldust(i)*dust_Vol(i)
        if (j==0) cycle
        mass2 = mass2 + nHges*eldust(i)*dust_mass(i)
        rhod2 = rhod2 + nHges*eldust(i)*dust_mass(i)
        Vcon2 = Vcon2 + nHges*eldust(i)*dust_Vol(i)
      enddo
      rhogr1 = mass1/Vcon1       
      rhogr2 = mass2/Vcon2
      do i=1,NDUST
        j = duind(i)
        if (j==0) then
          if (nHges*eldust(i)*dust_Vol(i)>0.05*Vcon1) then
            print'("*** important dust species without opacity ",
     >             "data:",A20,0pF5.2)',trim(dust_nam(i)),
     >           nHges*eldust(i)*dust_Vol(i)/Vcon1
          endif
        else
          Vs(j) = nHges*eldust(i)*dust_Vol(i)/Vcon2
          if (eldust(i)<=0.Q0) cycle
          print'(A20,1pE11.3)',trim(dust_nam(i)),Vs(j)
        endif
      enddo

      rho = nHges*muH
      print*,"dust material density [g/cm3]",rhogr1,rhogr2
      print*,"dust/gas mass ratio   [g/cm3]",rhod1/rho,rhod2/rho
      print*,"dust volume density [cm3/cm3]",Vcon1,Vcon2

      call SIZE_DIST(rho,rhogr2,Vcon2)
      
      do ilam=1,NLAM
        call effMedium(ilam,Vs,neff,keff)
        print*,lam(ilam),neff,keff
      enddo
      
      end

***********************************************************************
      SUBROUTINE SIZE_DIST(rho,rhogr,Vcon)
***********************************************************************
      use OPACITY,ONLY: NSIZE,aa,ff
      implicit none
      real,parameter :: pi=ACOS(-1.0)
      real,parameter :: mic=1.E-4
      real,intent(in) :: rho    ! gas mass density [g/cm3]
      real,intent(in) :: rhogr  ! dust material density [g/cm3]
      real,intent(in) :: Vcon   ! dust volume/H-nucleus [cm3]
      real :: rhoref,a1ref,a2ref,pp,VV,mm,Vref,mref,ndref,dg,scale
      real :: ndtest,Vtest,mtest
      real :: da,aweight(1000)
      integer :: i

      !------------------------------------------------
      ! ***  set up reference dust size dist.model  ***
      !------------------------------------------------
      NSIZE  = 100
      rhoref = 2.0              ! g/cm3
      a1ref  = 0.05             ! mic
      a2ref  = 1000.0           ! mic
      pp     = -3.5
      do i=1,NSIZE
        aa(i) = EXP(LOG(a1ref)+(i-1.0)/(NSIZE-1.0)*LOG(a2ref/a1ref))*mic
        ff(i) = aa(i)**pp
      enddo
      aweight = 0.0
      do i=2,NSIZE
        da = 0.5*(aa(i)-aa(i-1))
        aweight(i)   = aweight(i)   + da
        aweight(i-1) = aweight(i-1) + da
      enddo
      ndref = 0.0
      Vref  = 0.0
      mref  = 0.0
      do i=1,NSIZE
        VV = 4.0*pi/3.0*aa(i)**3
        mm = VV*rhoref
        ndref = ndref + ff(i)*aweight(i)
        Vref  = Vref  + ff(i)*VV*aweight(i)
        mref  = mref  + ff(i)*mm*aweight(i)
      enddo
      dg    = mref/rho             ! dust/gas mass ratio ...
      scale = 0.004/dg             ! ... which should be 0.004
      ff    = scale*ff             ! [cm-4]
      ndref = scale*ndref          ! [cm-3]
      Vref  = scale*Vref           ! [cm3/H-nucleus]

      !------------------------------------------------------
      ! ***  adjust dust sizes and volume while nd=const  ***
      !------------------------------------------------------
      scale   = (Vcon/Vref)**(1.0/3.0)
      aa      = scale*aa
      ff      = ff/scale
      aweight = scale*aweight
      !--- done, this is just a check ---
      ndtest  = 0.0
      Vtest   = 0.0
      mtest   = 0.0
      do i=1,NSIZE
        VV = 4.0*pi/3.0*aa(i)**3
        mm = VV*rhogr
        ndtest = ndtest + ff(i)*aweight(i)
        Vtest  = Vtest  + ff(i)*VV*aweight(i)
        mtest  = mtest  + ff(i)*mm*aweight(i)
      enddo
      dg = mtest/rho
      print*,"scale=",scale
      print*,"   nd=",ndref,ndtest
      print*,"  d/g=",dg
      print*,"Vdust=",Vref,Vtest,Vcon

      end
      
      
