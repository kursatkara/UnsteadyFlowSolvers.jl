function transpCoupled(surf::TwoDSurfThick, curfield::TwoDFlowField, ncell::Int64, nsteps::Int64 = 300, dtstar::Float64 = 0.015, startflag = 0, writeflag = 0, writeInterval = 1000., delvort = delNone(); maxwrite = 50, nround=6)

    # If a restart directory is provided, read in the simulation data
    if startflag == 0
        mat = zeros(0, 12)
        t = 0.
        tv = 0.
        del = zeros(ncell-1)
        E   = zeros(ncell-1)
        thick_orig = zeros(length(surf.thick))
        thick_orig_slope = zeros(length(surf.thick_slope))
        thick_orig[1:end] = surf.thick[1:end]
        thick_orig_slope[1:end] = surf.thick_slope[1:end]
        qu = zeros(length(surf.thick))

    elseif startflag == 1
        dirvec = readdir()
        dirresults = map(x->(v = tryparse(Float64,x); typeof(v) == Nothing ? 0.0 : v),dirvec)
        latestTime = maximum(dirresults)
        mat = DelimitedFiles.readdlm("resultsSummary")
        t = mat[end,1]
    else
        throw("invalid start flag, should be 0 or 1")
    end
    mat = mat'

    dt = dtstar*surf.c/surf.uref

    # if writeflag is on, determine the timesteps to write at
    if writeflag == 1
        writeArray = Int64[]
        tTot = nsteps*dt
        for i = 1:maxwrite
            tcur = writeInterval*real(i)
            if t > tTot
                break
            else
                push!(writeArray, Int(round(tcur/dt)))
            end
        end
    end

    vcore = 0.02*surf.c

    int_wax = zeros(surf.ndiv)
    int_c = zeros(surf.ndiv)
    int_t = zeros(surf.ndiv)

    # initial momentum and energy shape factors

    delfvm, E, xfvm, quf, quf0 = initViscous(ncell)
    xfvm = xfvm/pi
    qu = zeros(surf.ndiv)

    delInter = Spline1D(xfvm, delfvm)


    delu = evaluate(delInter, surf.theta)
    dell = delu

    #dt = 0.0005  #initStepSize(surf, curfield, t, dt, 0, writeArray, vcore, int_wax, i

    for istep = 1:nsteps

        t = t + dt

        #Update kinematic parameters
        update_kinem(surf, t)

        #Update flow field parameters if any
        update_externalvel(curfield, t)

        #Update bound vortex positions
        update_boundpos(surf, dt)

        #Update incduced velocities on airfoil
        update_indbound(surf, curfield)

        #Set up the matrix problem
        surf, xloc_tev, zloc_tev = update_thickLHS(surf, curfield, dt, vcore)

        #Construct RHS vector
        update_thickRHS(surf, curfield)

        #Place dummy  TEV
        push!(curfield.tev, TwoDVort(xloc_tev, zloc_tev, 0.0, vcore, 0., 0.))

        #Initial condition for iteration
        x_init = [surf.aterm[:]; surf.bterm[:]; curfield.tev[end].s; delu[:]; dell[:]]

        if istep == 0
            quf0 = quf
        end

        iter = iterIBLsolve(surf, curfield, quf, quf0, dt, xfvm, E)

        soln = nlsolve(not_in_place(iter), x_init, method = :newton)

        xsoln= soln.zero
        #Assign solution
        surf.aterm[:] = xsoln[1:surf.naterm]
        surf.bterm[:] = xsoln[surf.naterm+1:2*surf.naterm]
        curfield.tev[end].s = xsoln[2*surf.naterm+1]
        delu[:] = xsoln[2*surf.naterm+2:2*surf.naterm+1+surf.ndiv]
        delu[:] = xsoln[2*surf.naterm+surf.ndiv+2:2*surf.naterm+1+2*surf.ndiv]

        #Calculate adot
        update_atermdot(surf, dt)

        #Set previous values of aterm to be used for derivatives in next time step
        surf.a0prev[1] = surf.a0[1]
        for ia = 1:3
            surf.aprev[ia] = surf.aterm[ia]
        end

        #Calculate bound vortex strengths
        update_bv_src(surf)

        #Wake rollup
        wakeroll(surf, curfield, dt)

        #Force calculation
        cnc, cnnc, cn, cs, cl, cd, int_wax, int_c, int_t = calc_forces(surf, int_wax, int_c, int_t, dt)

        mat = hcat(mat,[t, surf.kinem.alpha, surf.kinem.h, surf.kinem.u, vle,
                     cl, cd, cnc, cnnc, cn, cs, stag])


        quf0[1:end] = quf[1:end];

    end

    mat = mat'

    f = open("resultsSummary", "w")
    Serialization.serialize(f, ["#time \t", "alpha (deg) \t", "h/c \t", "u/uref \t", "A0 \t", "Cl \t", "Cd \t", "Cm \n"])
    DelimitedFiles.writedlm(f, mat)
    close(f)

mat, surf, curfield, del, E, quf, qu,thick_orig, thick_orig_slope

end
