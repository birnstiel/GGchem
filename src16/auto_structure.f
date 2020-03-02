***********************************************************************
      SUBROUTINE AUTO_STRUCTURE
***********************************************************************
      use PARAMETERS,ONLY: Rpl,Mpl,Tmax,pmin,pmax,gamma,verbose,
     >                     model_eqcond,remove_condensates,Npoints
      use CHEMISTRY,ONLY: NELM,NMOLE,elnum,cmol,catm,el,charge
      use DUST_DATA,ONLY: NELEM,NDUST,elnam,eps0,bk,bar,amu,grav,
     >                    muH,mass,mel,
     >                    dust_nam,dust_mass,dust_Vol,
     >                    dust_nel,dust_el,dust_nu
      use EXCHANGE,ONLY: nel,nat,nion,nmol,mmol,H,C,N,O
      implicit none
      integer,parameter :: qp = selected_real_kind ( 33, 4931 )
      character(len=20) :: name,short_name(NDUST)
      real(kind=qp) :: eps(NELEM),eps00(NELEM)
      real(kind=qp) :: Sat(NDUST),eldust(NDUST),out(NDUST)
      real(kind=qp) :: fac,e_reservoir(NELEM),d_reservoir(NDUST)
      real :: rho,Tg,p,kT,nHges,nges,pgas,ff,fold,mu,muold,dmu,dfdmu
      real :: p1,p2,T1,T2,g1,g2,mu1,mu2,rho1,rho2
      real :: zz,dz,Hp,kappa,rhog,rhod,dustV,km=1.D+5
      integer :: i,j,k,e,ip,jj,it,NOUT
      logical :: outAllHistory=.false.
      
      !-----------------------------------------------------------
      ! ***  compute base point with equilibrium condensation  ***
      !-----------------------------------------------------------
      Tg = Tmax
      p  = pmax
      mu = muH
      do it=1,99
        nHges = p*mu/(bk*Tg)/muH
        call EQUIL_COND(nHges,Tg,eps,Sat,eldust,verbose)
        call GGCHEM(nHges,Tg,eps,.false.,0)
        kT   = bk*Tg
        nges = nel
        rho  = nel*mel
        do j=1,NELEM
          nges = nges + nat(j)
          rho  = rho  + nat(j)*mass(j)
        enddo
        do j=1,NMOLE
          nges = nges + nmol(j)
          rho  = rho  + nmol(j)*mmol(j)
        enddo
        pgas = nges*kT
        ff   = p-pgas
        if (it==1) then
          muold = mu
          mu = nHges/pgas*(bk*Tg)*muH
          dmu = mu-muold
        else
          dfdmu = (ff-fold)/(mu-muold)
          dmu   = -ff/dfdmu
          muold = mu
          if ((dmu>0.0).or.ABS(dmu/mu)<0.7) then
            mu = muold+dmu
          else
            mu = nHges/pgas*(bk*Tg)*muH
          endif  
        endif
        fold = ff
        print '("p-it=",i3,"  mu=",2(1pE20.12))',it,mu/amu,dmu/mu
        if (ABS(dmu/mu)<1.E-10) exit
      enddo  

      !------------------------------------------------
      ! ***  reset total <- gas element abundances  ***
      !------------------------------------------------
      nHges  = nHges*eps(H)   ! in the gas phase over the crust
      fac    = 1.Q0/eps(H)
      eps    = fac*eps        ! nomalise to have eps(H)=1
      eps0   = eps
      muH    = rho/nHges      ! in the gas phase over the crust
      mu     = rho/nges       ! in the gas phase over the crust
      eldust = 0.Q0           ! no condensates in that gas
      e_reservoir = 0.Q0
      d_reservoir = 0.Q0
      eps00 = eps0
      print*
      print'("mu[amu]=",1pE11.3)',mu/amu
      do e=1,NELM
        if (e==el) cycle
        j = elnum(e) 
        print'("eps(",A2,")=",1pE11.3)',elnam(j),eps(j)
      enddo

      !----------------------------
      ! ***  open output files  ***
      !----------------------------
      do i=1,NDUST
        name = dust_nam(i) 
        j=index(name,"[s]")
        short_name(i) = name
        if (j>0) short_name(i)=name(1:j-1)
      enddo
      NOUT = NELM
      if (charge) NOUT=NOUT-1
      open(unit=70,file='Static_Conc.dat',status='replace')
      write(70,1000) 'H',eps( H), 'C',eps( C),
     &               'N',eps( N), 'O',eps( O)
      write(70,*) NOUT,NMOLE,NDUST,Npoints
      write(70,2000) 'Tg','nHges','pgas','el',
     &               (trim(elnam(elnum(j))),j=1,el-1),
     &               (trim(elnam(elnum(j))),j=el+1,NELM),
     &               (trim(cmol(i)),i=1,NMOLE),
     &               ('S'//trim(short_name(i)),i=1,NDUST),
     &               ('n'//trim(short_name(i)),i=1,NDUST),
     &               ('eps'//trim(elnam(elnum(j))),j=1,el-1),
     &               ('eps'//trim(elnam(elnum(j))),j=el+1,NELM),
     &               'dust/gas','dustVol/H'
      open(unit=71,file='Structure.dat',status='replace')
      write(71,2000) 'z[km]','rho[g/cm3]','pgas[dyn/cm2]','T[K]',
     &               'n<H>[cm-3]','mu[amu]','g[m/s2]','Hp[km]'

      !-----------------------------------------------------------
      ! ***  construct a polytopic atmosphere above the crust  ***
      ! ***  in hydrostatic equilibrium using dp/dz = - rho g  ***
      ! ***  and  T = const p**kappa.                          ***
      !-----------------------------------------------------------
      kappa = (gamma-1.0)/gamma      ! polytrope index T ~ p^kappa 
      zz    = 0.0                    ! height [cm] 
      T1    = Tg                     ! temperature [K]
      p1    = pgas                   ! pressure [dyn/cm2]
      rho1  = rho                    ! gas mass density [g/cm3]
      mu1   = mu                     ! mean molecular weight [g]
      g1    = grav*Mpl/(Rpl+zz)**2   ! gravity [cm/s2]

      do ip=1,Npoints
        Hp  = bk*T1/(mu1*g1)         ! pressure scale height

        !--- compute properties of condensates ---
        rhod  = 0.0
        dustV = 0.0
        do jj=1,NDUST
          rhod  = rhod  + nHges*eldust(jj)*dust_mass(jj)
          dustV = dustV + eldust(jj)*dust_Vol(jj)
          out(jj) = LOG10(MIN(1.Q+300,MAX(1.Q-300,Sat(jj))))
          if (ABS(Sat(jj)-1.Q0)<1.E-10) out(jj)=0.Q0
        enddo  
        call SUPERSAT(T1,nat,nmol,Sat)

        !--- output stuff ---
        write(70,2010) T1,nHges,p1,
     &       LOG10(MAX(1.Q-300, nel)),
     &      (LOG10(MAX(1.Q-300, nat(elnum(jj)))),jj=1,el-1),
     &      (LOG10(MAX(1.Q-300, nat(elnum(jj)))),jj=el+1,NELM),
     &      (LOG10(MAX(1.Q-300, nmol(jj))),jj=1,NMOLE),
     &      (out(jj),jj=1,NDUST),
     &      (LOG10(MAX(1.Q-300, eldust(jj))),jj=1,NDUST),
     &      (LOG10(eps(elnum(jj))),jj=1,el-1),
     &      (LOG10(eps(elnum(jj))),jj=el+1,NELM),
     &       LOG10(MAX(1.Q-300, rhod/rho1)),
     &       LOG10(MAX(1.Q-300, dustV))
        write(71,2011) zz/km,rho1,p1,T1,nHges,mu1/amu,g1/100.0,Hp/km

        !-----------------------------------------------------------------
        ! ***  solve chemistry, hydrostatic equilibrium and T~p^kappa  ***
        ! ***  dT/dz = dT/dp dp/dz = -kappa T/p rho g = -kappa mu/k g. ***
        ! ***  eps0(:) and hence muH = rho/n<H> do not change.         ***
        !-----------------------------------------------------------------
        dz  = LOG(pmax/pmin)*Hp/Npoints                 ! step in height
        g2  = grav*Mpl/(Rpl+zz+dz)**2                   ! gravity there
        mu2 = mu1                                       ! initial guess
        do it=1,99
          T2    = T1 - kappa/bk*0.5*(mu2*g2+mu1*g1)*dz
          p2    = p1*(T2/T1)**(1.0/kappa)               ! target pressure
          rho2  = p2*mu2/(bk*T2)
          nHges = rho2/muH                              ! estimated n<H>
          if (model_eqcond) then
            call EQUIL_COND(nHges,T2,eps,Sat,eldust,verbose)
          else
            eps(:) = eps0(:)
          endif  
          call GGCHEM(nHges,T2,eps,.false.,0)
          kT = bk*T2
          nges = nel
          do j=1,NELEM
            nges = nges + nat(j)
          enddo
          do j=1,NMOLE
            nges = nges + nmol(j)
          enddo
          pgas = nges*kT                                ! gas pressure
          ff   = p2-pgas                                ! remaining error
          if (it==1) then
            muold = mu2
            mu2 = nHges/pgas*(bk*T2)*muH
            dmu = mu2-muold
          else
            dfdmu = (ff-fold)/(mu2-muold)
            dmu   = -ff/dfdmu
            !write(98,'(I3,99(1pE14.7))')
     >      !     it,muold,mu2,fold,ff,dfdmu,dmu/mu2
            muold = mu2
            if ((dmu>0.0).or.ABS(dmu/mu2)<0.7) then
              mu2 = muold+dmu
            else
              mu2 = nHges/pgas*(bk*T2)*muH
            endif  
          endif
          fold = ff
          print '("p-it=",i3,"  mu=",2(1pE20.12))',it,mu2/amu,dmu/mu2
          if (ABS(dmu/mu2)<1.E-10) exit
        enddo  
        !print*,p2,pgas
        !print*,bk/kappa*(T2-T1),-0.5*(mu1*g1+mu2*g2)*dz
        !print*,p1**(1-gamma)*T1**gamma,p2**(1-gamma)*T2**gamma
        !print*,DLOG(p2/p1)/dz,-0.5/bk*(mu1*g1/T1+mu2*g2/T2)

        !--- make step ---
        zz   = zz+dz
        p1   = p2
        T1   = T2
        rho1 = rho2
        mu1  = mu2
        g1   = g2

        !--- remove all condensates and put them into the reservoir? ---
        if (remove_condensates) then
          fac = 1.Q+0
          do j=1,NDUST
            d_reservoir(j) = d_reservoir(j) + fac*eldust(j)
            do jj=1,dust_nel(j)
              k = dust_el(j,jj)
              e_reservoir(k) = e_reservoir(k) 
     &                       + fac*dust_nu(j,jj)*eldust(j)
            enddo
          enddo  
          do j=1,NELM
            if (j==el) cycle 
            k = elnum(j)
            print'(A3,2(1pE18.10))',elnam(k),eps(k)/eps00(k),
     &                      (eps(k)+e_reservoir(k))/eps00(k)
          enddo
          eps0(:) = eps(:) + (1.Q0-fac)*e_reservoir(:) ! remove elements
          !--- choice of output ---
          if (outAllHistory) then                      ! output will contain:
            eldust(:) = d_reservoir(:)                 ! all condensates ever
          else 
            eldust(:) = eldust(:)                      ! only local condensates
          endif
          muH = 0.d0
          do j=1,NELM
            if (j==el) cycle
            k = elnum(j)
            muH = muH + mass(k)*eps0(k)                ! re-compute muH
          enddo
          nHges = rho1/muH
        endif  

      enddo
      close(70)
      close(71)

 1000 format(4(' eps(',a2,') = ',1pD8.2))
 1010 format(A4,0pF8.2,3(a6,1pE9.2),1(a11,1pE9.2))
 2000 format(9999(1x,A19))
 2010 format(0pF20.6,2(1pE20.6),9999(0pF20.7))
 2011 format(9999(1x,1pE19.10))
      end
