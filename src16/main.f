***********************************************************************
      PROGRAM EQ_CHEMISTRY
***********************************************************************
      use PARAMETERS,ONLY: model_dim,model_struc,model_eqcond,
     >                     useDatabase
      use EXCHANGE,ONLY: chemcall,chemiter,ieqcond,ieqconditer,
     >                   itransform
      use DATABASE,ONLY: NLAST
      implicit none

      call READ_PARAMETER
      call INIT
      call INIT_CHEMISTRY
      call INIT_DUSTCHEM
      
      if (model_dim==0) then
        call DEMO_CHEMISTRY
      else if (model_dim==1) then  
        if (model_struc==0) then 
          call DEMO_SWEEP
        else  
          call DEMO_STRUCTURE
        endif 
      else if (model_dim==2) then  
        call DEMO_PHASEDIAGRAM
      else
        print*,'*** model_dim=',model_dim,' ???'
        stop
      endif   
      
      print*
      print'("         smchem calls = ",I8)',chemcall
      print'("      iterations/call = ",0pF8.2)',
     >                     REAL(chemiter)/REAL(chemcall)
      if (model_eqcond) then
        print'("eq condensation calls = ",I8)',ieqcond
        print'("   eq iterations/call = ",0pF8.2)',
     >                   REAL(ieqconditer)/REAL(ieqcond)
        print'("      transform calls = ",I8)',itransform
        NLAST=0         ! also save replaced database entries
        if (useDatabase) call SAVE_DBASE
      endif

      end


***********************************************************************
      SUBROUTINE DEMO_CHEMISTRY
***********************************************************************
      use PARAMETERS,ONLY: nHmax,Tmax,pmax,model_pconst,model_eqcond,
     >                     verbose 
      use CHEMISTRY,ONLY: NMOLE,NELM,m_kind,elnum,cmol,el
      use DUST_DATA,ONLY: NELEM,NDUST,elnam,eps0,bk,bar,amu,
     >                    muH,mass,mel,
     >                    dust_nam,dust_mass,dust_Vol,dust_nel,dust_el
      use EXCHANGE,ONLY: nel,nat,nion,nmol,mmol,C,N,O,Si
      implicit none
      integer,parameter  :: qp = selected_real_kind ( 33, 4931 )
      real(kind=qp) :: eps(NELEM),Sat(NDUST),eldust(NDUST)
      real(kind=qp) :: nmax,threshold,deps
      real*8  :: Tg,nHges,p,mu,muold,pgas,fold,ff,dfdmu,dmu,mugas
      real*8  :: rhog,rhoc,rhod,d2g,mcond,mgas,Vcon,Vcond,Vgas,ngas
      integer :: i,imol,iraus,e,aIraus,aIIraus,j,verb,dk,it
      logical :: included,haeufig,raus(NMOLE)
      logical :: rausI(NELEM),rausII(NELEM)
      character(len=10) :: sp

      !deps = eps0(Si)*0.1*(1.0-108./200.)
      !eps0(Si) = eps0(Si) + deps
      !eps0(O)  = eps0(O)  + deps*2
      
      Tg    = Tmax
      nHges = nHmax
      p     = pmax
      eps   = eps0
      mu    = muH
      eldust = 0.Q0
      verb = verbose
      if (model_eqcond) verb=0

      do it=1,999
        if (model_pconst) nHges = p*mu/(bk*Tg)/muH
        if (model_eqcond) then
          call EQUIL_COND(nHges,Tg,eps,Sat,eldust,verbose)
        endif
        call GGCHEM(nHges,Tg,eps,.false.,verb)
        ngas = nel
        do j=1,NELEM
          ngas = ngas + nat(j)
        enddo
        do j=1,NMOLE
          ngas = ngas + nmol(j)
        enddo
        pgas  = ngas*bk*Tg
        ff    = p-pgas
        if (it==1) then
          muold = mu
          mu = nHges/pgas*(bk*Tg)*muH
          dmu = mu-muold
          if (.not.model_pconst) exit
        else
          dfdmu = (ff-fold)/(mu-muold)
          dmu   = -ff/dfdmu
          !write(98,'(I3,99(1pE14.7))') it,muold,mu,fold,ff,dfdmu,dmu/mu
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

      print*
      write(*,*) '----- total nuclei dens. and fractions in gas -----'
      do e=1,NELM
        if (e==el) cycle
        i = elnum(e) 
        write(*,'(" n<",A2,">=",1pE10.4,2x,1pE10.4)')
     >      elnam(i),nHges*eps(i),eps(i)/eps0(i)
      enddo  

      ngas = nel      ! cm-3
      rhog = nel*mel  ! g cm-3
      do j=1,NELEM
        ngas = ngas + nat(j)
        rhog = rhog + nat(j)*mass(j)
      enddo
      do j=1,NMOLE
        ngas = ngas + nmol(j)
        rhog = rhog + nmol(j)*mmol(j)
      enddo
      rhod = 0.d0     ! g cm-3  
      Vcon = 0.d0     ! cm3
      do i=1,NDUST
        if (eldust(i)<=0.Q0) cycle 
        rhod = rhod + nHges*eldust(i)*dust_mass(i)
        Vcon = Vcon + nHges*eldust(i)*dust_Vol(i)
      enddo  
      mugas = rhog/ngas             ! mean molecular weight [g]
      d2g   = rhod/rhog             ! dust/gas mass ratio [-]
      rhoc  = rhod/Vcon             ! condensed matter density [g cm-3]
      mcond = 1.0                   ! mass of condensates [= 1 g]
      Vcond = mcond/rhoc            ! volume of condensates [cm3]
      mgas  = mcond/d2g             ! mass of gas [g]
      Vgas  = mgas/mugas*bk*Tg/pgas ! volume of gas [cm3]
      
      print*
      write(*,*) '----- bulk properties -----'
      print'("for Tg[K]=",0pF8.2," and n<H>[cm-3]=",1pE10.3)',Tg,nHges
      print'(16x,3(A12))',"condensates","gas","check"
      print'("         mass[g]",2(1pE12.4))',mcond,mgas
      print'("  density[g/cm3]",2(1pE12.4))',rhoc,rhog
      print'("tot.dens.[g/cm3]",12x,2(1pE12.4))',nHges*muH,
     >                                   (mcond+mgas)/Vgas
      print'("     volume[cm3]",2(1pE12.4))',Vcond,Vgas
      print'("   pressure[bar]",12x,1pE12.4)',pgas/bar
      print'("  el.press.[bar]",12x,1pE12.4)',nel*bk*Tg/bar
      print'(" mol.weight[amu]",12x,1pE12.4)', mugas/amu
      print'("         mu[amu]",12x,2(1pE12.4))', mu/amu,
     >                (mcond+mgas)/Vgas/pgas*(bk*Tg)/amu
      print'("        muH[amu]",12x,2(1pE12.4))',muH/amu,
     >                     (mcond+mgas)/(nHges*Vgas)/amu
      
      print*
      write(*,*) '----- condensates [cm3] [mfrac] [Vfrac] -----'
      raus = .false.
      do 
        iraus = 0
        nmax  = 0.Q0
        do i=1,NDUST
          if (raus(i).or.eldust(i)<=0.Q0) cycle 
          if (eldust(i)>nmax) then
            iraus = i
            nmax = eldust(i)
          endif
        enddo
        if (iraus==0) exit
        raus(iraus) = .true.
        write(*,1020) ' n'//trim(dust_nam(iraus))//'=',
     >                eldust(iraus)*nHges,
     >                eldust(iraus)*dust_mass(iraus)*nHges/rhod,
     >                eldust(iraus)*dust_Vol(iraus)*nHges/Vcon
      enddo
  
      print*
      write(*,*) '----- atoms and ions [cm3] -----'
      write(*,1000) ' nel=',nel
      do e=1,NELM
        if (e==el) cycle
        i = elnum(e) 
        write(*,1010) ' n'//trim(elnam(i))//'I=',nat(i),
     >               '  n'//trim(elnam(i))//'II=',nion(i)
      enddo
  
      write(*,*) '----- most abundant species [cm3] [molfrac] -----'
      raus   = .false.
      rausI  = .false.
      rausII = .false.
      do
        iraus   = 0
        aIraus  = 0
        aIIraus = 0
        nmax  = 0.Q0
        do i=1,NMOLE
          if ((nmol(i).gt.nmax).and.(.not.raus(i))) then
            iraus = i
            nmax  = nmol(i)
          endif
        enddo
        do e=1,NELM
          if (e==el) cycle
          i = elnum(e) 
          if ((nat(i).gt.nmax).and.(.not.rausI(i))) then
            iraus = 0
            aIraus = i
            aIIraus = 0
            nmax  = nat(i)
          endif
          if ((nion(i).gt.nmax).and.(.not.rausII(i))) then
            iraus = 0
            aIraus = 0
            aIIraus = i
            nmax  = nion(i)
          endif
        enddo
        haeufig = (nmax.gt.ngas*1.Q-12)
        if (.not.haeufig) exit
        if (iraus>0) then
          raus(iraus) = .true.
          write(*,4010) cmol(iraus),nmol(iraus),nmol(iraus)/ngas
        else if (aIraus>0) then 
          rausI(aIraus) = .true.
          write(*,4010) elnam(aIraus)//"I       ",
     >                  nat(aIraus),nat(aIraus)/ngas
        else if (aIIraus>0) then 
          rausII(aIIraus) = .true.
          write(*,4010) elnam(aIIraus)//"II     ",
     >                  nat(aIIraus),nion(aIIraus)/ngas
        endif  
      enddo
  
      print*
      write(*,*) '-----  where are the elements?  -----'
      do e=1,NELM
        i = elnum(e)
        if (e==el) then
          write(*,'("    Element ",A2,1pE15.3)') 'el',0.Q0
          write(*,'(1x,A18,1pE10.3)') "nel",nel
          threshold = 1.Q-3*nel
        else   
          write(*,'("    Element ",A2,1pE15.3)') elnam(i),eps0(i)*nHges 
          threshold = eps(i)*nHges*1.D-2
          if (nat(i).gt.eps(i)*nHges*1.D-2) then
            write(*,'(1x,A18,1pE10.3)') "n"//trim(elnam(i)), nat(i) 
          endif  
        endif  

        raus = .false.
        do 
          iraus = 0
          nmax  = 0.Q0
          do dk=1,NDUST
            if (eldust(dk)<=0.Q0) cycle 
            included = .false. 
            do j=1,dust_nel(dk)
              if (i==dust_el(dk,j)) then
                included = .true.
              endif
            enddo  
            if (included) then
              if ((eldust(dk).gt.nmax).and.(.not.raus(dk))) then
                iraus = dk
                raus(dk) = .true.
                nmax = eldust(dk)
              endif  
            endif
          enddo  
          if (nmax==0.Q0) exit
          write(*,'(1x,A18,1pE10.3)') 
     >          "n"//trim(dust_nam(iraus)),eldust(iraus)*nHges 
        enddo  

        raus = .false.
        do 
          iraus = 0
          nmax  = 0.Q0
          do imol=1,NMOLE
            sp = cmol(imol) 
            if ((nmol(imol).gt.nmax).and.(.not.raus(imol))) then
              included = .false. 
              do j=1,m_kind(0,imol)
                if (e==m_kind(j,imol)) included=.true.
              enddo  
              if (included) then
                iraus = imol
                nmax = nmol(imol)
              endif  
            endif
          enddo  
          haeufig = (nmax.gt.threshold)
          if (.not.haeufig) exit
          write(*,'(1x,A18,1pE10.3)') "n"//trim(cmol(iraus)),nmol(iraus)
          raus(iraus) = .true.
        enddo
      enddo  

*     ------------------------------
      call SUPERSAT(Tg,nat,nmol,Sat)
*     ------------------------------
      print*
      write(*,*) '----- supersaturation ratios -----'
      do i=1,NDUST
        if (Sat(i)<1.Q-2) cycle 
        write(*,5000) dust_nam(i),Sat(i) 
      enddo  

 1000 format(a6,1pE9.3)
 1010 format(a6,1pE9.3,a8,1pE9.3)
 1020 format(a22,1pE15.9,2(0pF10.5))
 4000 format(a7,1pE10.4,a5,1pE10.4)     
 4010 format(' n',a8,1pE12.4,0pF13.9)
 5000 format(1x,a20,' S=',1pE9.3)
      RETURN
      end      
