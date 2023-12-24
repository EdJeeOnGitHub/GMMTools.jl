using Pkg
Pkg.activate(".")
Pkg.resolve()
Pkg.instantiate()

using Revise
using LinearAlgebra # for identity matrix "I"
using CSV
using DataFrames
using FixedEffectModels # for benchmarking
using RegressionTables

using GMMTools
using Optim # need for NewtonTrustRegion()


# load data, originally from: https://www.kaggle.com/datasets/uciml/autompg-dataset/?select=auto-mpg.csv 
    df = CSV.read("examples/auto-mpg.csv", DataFrame)
    df[!, :constant] .= 1.0


# Run plain OLS for comparison
    r = reg(df, term(:mpg) ~ term(:acceleration))
    regtable(r)

# define moments for OLS regression
# residuals orthogonal to the constant and to the variable (acceleration)
# this must always return a Matrix (rows = observations, columns = moments)
function ols_moments_fn(data, theta)
    
    resids = @. data.mpg - theta[1] - theta[2] * data.acceleration
    
    # n by 2 matrix of moments
    moms = hcat(resids, resids .* data.acceleration)
    
    return moms
end

# initial parameter guess
    theta0 = randn(20,2)

### using Optim.jl
    # estimation options
    myopts = GMMTools.GMMOptions(
                    path="C:/git-repos/GMMTools.jl/examples/temp/", 
                    optimizer=:lsqfit,
                    optim_algo_bounds=true,
                    lower_bound=[-Inf, -Inf],
                    upper_bound=[Inf, Inf],
                    optim_autodiff=:forward,
                    write_iter=true,
                    clean_iter=true,
                    overwrite=true,
                    trace=1)

    # estimate model
    myfit = GMMTools.fit(df, ols_moments_fn, theta0, mode=:twostep, opts=myopts)

### using Optim.jl
    # estimation options
    myopts = GMMTools.GMMOptions(
                    path="C:/git-repos/GMMTools.jl/examples/temp/", 
                    optim_algo=LBFGS(), 
                    optim_autodiff=:forward,
                    write_iter=true,
                    clean_iter=true,
                    overwrite=true,
                    trace=1)

    # estimate model
    myfit = GMMTools.fit(df, ols_moments_fn, theta0, mode=:twostep, opts=myopts)

# compute asymptotic variance-covariance matrix and save in myfit.vcov
    vcov_simple(df, ols_moments_fn, myfit)

# print table with results

    # temp = GMMTools.GMMModel(myfit)
    # dfsdfsdf
    # RegressionTables.get_coefname()
    # # formula_schema
    # formula(temp)

    # temp = GMMTools.GMMModel(myfit)
    # formula(temp)
    # display(temp)

    # dsfd
    # RegressionTables.formula(m::GMMModel) = term(m.responsename) ~ sum(term.(String.(m.coefnames)))

    regtable(myfit)

fsdfds
    f1 = term("mpg") ~ term("acceleration") + term("acceleration2")
    get_coefname(f1.rhs)


    

sdf





# compute Bayesian (weighted) bootstrap inference and save in myfit.vcov
    myopts.trace = 0
    vcov_bboot(df, ols_moments_fn, theta0, myfit, nboot=500, opts=myopts)
    GMMTools.regtable(myfit) # print table with new bootstrap SEs -- very similar to asymptotic SEs in this case. Nice!


# bootstrap with weightes drawn at the level of clusters defined by the variable df.cylinders
    vcov_bboot(df, ols_moments_fn, theta0, myfit, boot_weights=:cluster, cluster_var=:cylinders, nboot=500, opts=myopts)
    myfit.vcov

    GMMTools.regtable(myfit)

