#= 
TODOS:
1. add try ... catch blocks
1. add optimizer options / variants. Where to save the optimizer-specific options? kwargs.
1. save bootstrap weights?
1. add parameter names in the problem object
1. switch to PrettyTables.jl (cf Peter's suggestion)
=#


Base.@kwdef mutable struct GMMProb
    data::DataFrame
    data_other = nothing
    mom_fn::Function
    W=I
    theta0::Array
    weights
    # TODO: add parameter names (optional)
end

function create_GMMProb(;data, data_other=nothing, mom_fn, W=I, theta0, weights=1.0)

    if isa(theta0, Vector)
        theta0 = Matrix(Transpose(theta0))
    end

    return GMMProb(data, data_other, mom_fn, W, theta0, weights) 
end

Base.@kwdef mutable struct GMMResult
    theta0::Vector
    theta_hat::Vector
    obj_value::Number
    converged::Bool
    iterations::Integer
    iteration_limit_reached::Bool
    time_it_took::Float64
    all_results = nothing # TODO: switch to PrettyTables.jl and OrderedDict
    idx = nothing # aware of which iteration number this is

end

function table(r::GMMResult)

    if !isnothing(r.all_results)
        return r.all_results
    end

    all_results = DataFrame(
        "idx" => [isnothing(r.idx) ? 1 : r.idx],
        "obj_value" => [r.obj_value],
        "converged" => [r.converged],
        "iterations" => [r.iterations],
        "iteration_limit_reached" => [r.iteration_limit_reached],
        "time_it_took" => [r.time_it_took],
    )
    
    # estimated parameters
    nparams = length(r.theta_hat)
    all_results[!, "theta_hat"] = [r.theta_hat]

    # initial conditions
    all_results[!, "theta0"] = [r.theta0]

    return all_results
end

function Base.show(io::IO, r::GMMResult)
    println("θ hat    = ", r.theta_hat)
    println("Converged? ", r.converged)
    println("Obj value  ", r.obj_value)
    display(r.all_results)
end

Base.@kwdef mutable struct GMMBootResults
    all_results
    all_results_allbootruns
end

function Base.show(io::IO, r::GMMBootResults)
    println("Baysian bootstrap results")
    display(r.all_results)
    display(r.all_results_allbootruns)
end


### Initial conditions

"""
Creates a random matrix of initial conditions, taking bounds into account
"""
function random_theta0(theta0::Vector, nic::Int; theta_lower=nothing, theta_upper=nothing)

    n_params = length(theta0)
    theta0_mat = zeros(nic, n_params)
    isnothing(theta_lower) && (theta_lower = fill(-Inf, n_params))
    isnothing(theta_upper) && (theta_upper = fill( Inf, n_params))

    for i=1:nic
        for j=1:n_params

            θL = theta_lower[j]
            θH = theta_upper[j]

            if (θL == -Inf) & (θH == Inf)
                theta0_mat[i,j] = (-1.5 + 3.0 * rand()) * theta0[j]
            elseif (θL > -Inf) & (θH == Inf)
                theta0_mat[i,j] = θL + (theta0[j] - θL) * (0.5 + rand())
            elseif (θL == -Inf) & (θH < Inf)
                theta0_mat[i,j] = θH - (θH - theta0[j]) * (0.5 + rand())
            else
                @assert (θL > -Inf) & (θH < Inf)
                theta0_mat[i,j] = θL + (θH - θL) * rand()
            end
        end
    end

    return theta0_mat
end


function process_results(est_results::Vector{GMMResult})
    obj_values = [er.obj_value for er = est_results]
    idx = argmin(obj_values)

    best_result = est_results[idx]

    best_result.all_results = vcat([table(er) for er = est_results]...)
    best_result.all_results[!, :is_optimum] = ((1:length(est_results)) .== idx) .+ 0
    
    # sort!(best_result.all_results, :obj_value)

    return best_result
end


Base.@kwdef mutable struct GMMOptions
    path::String = ""
    optim_opts = nothing
    write_iter::Bool = false  # write results to file along the way?
    clean_iter::Bool = false  # 
    overwrite::Bool = false
    debug::Bool = false
end

Base.copy(x::GMMOptions) = GMMOptions([getfield(x, k) for k ∈ fieldnames(GMMOptions)]...)

function write(est_result::GMMResult, opts::GMMOptions; subpath="", filename="")
    if opts.path == ""
        return
    end

    if subpath == ""
        full_path = opts.path
    else
        (subpath[end] != "/") && (subpath *= "/")
        full_path = opts.path * subpath
        isdir(full_path) || mkdir(full_path)
    end

    (filename == "") ? filename = "results.csv" : nothing

    file_path = full_path * filename

    CSV.write(file_path, table(est_result))
end

function write(boot_results::GMMBootResults, opts::GMMOptions)
    if opts.path == ""
        return
    end

    # temp_df = DataFrame(boot_results.table, :auto)

    CSV.write(opts.path * "results_boot.csv", boot_results.all_results)
    CSV.write(opts.path * "results_boot_all.csv", boot_results.all_results_allbootruns)
end

function parse_vector(s::String)
    return parse.(Float64, split(s[2:(end-1)],","))
end

function load(opts::GMMOptions, filepath::String)

    full_path = opts.path * filepath
    if isfile(full_path)
        df = CSV.read(full_path, DataFrame)

        if nrow(df) == 1
            return GMMResult(
                theta0=parse_vector(df[1, :theta0]),
                theta_hat=parse_vector(df[1, :theta_hat]),
                converged=df[1, :converged],
                obj_value=df[1, :obj_value],
                iterations=df[1, :iterations],
                iteration_limit_reached=df[1, :iteration_limit_reached],
                time_it_took=df[1, :time_it_took],
                idx=df[1, :idx])
        
        else
            
                mysample = df.is_optimum .== 1
                df_optimum = df[mysample, :]
            return GMMResult(
                theta0=parse_vector(df_optimum[1, :theta0]),
                theta_hat=parse_vector(df_optimum[1, :theta_hat]),
                converged=df_optimum[1, :converged],
                obj_value=df_optimum[1, :obj_value],
                iterations=df_optimum[1, :iterations],
                iteration_limit_reached=df_optimum[1, :iteration_limit_reached],
                time_it_took=df_optimum[1, :time_it_took],
                idx=df_optimum[1, :idx],
                all_results=df)

            # @error "load large DF not yet supported"
        end
    else
        return nothing
    end
end




###### GMM

function gmm_objective(theta::Vector, model::GMMProb; debug::Bool=false)

    t1 = @elapsed m = model.mom_fn(model, theta)

    @assert isa(m, Vector) || (isa(m, Matrix) && size(m,2) == 1) "mom_fn should return a vector or vertical (K x 1) matrix."
    
    debug && println("Evaluation took ", t1)
    
    return (Transpose(m) * model.W * m)[1]
end

"""
overall: one or multiple initial conditions
"""
function fit(model::GMMProb; setup_fn::Union{Function, Nothing}=nothing, run_parallel=true, opts=GMMOptions())

    # skip if output file already exists
    if !opts.overwrite && (opts.path != "")
        
        opt_results_from_file = load(opts, "results.csv")
        
        if !isnothing(opt_results_from_file)
            println(" Results already exist. Reading from file.")
            return opt_results_from_file
        end
    end

    # Initial computation (if provided)
    if !isnothing(setup_fn)
        setup_fn(model)
    end

    # number of initial conditions (and always format as matrix, rows=iterations, columns=paramters)
    nic = size(model.theta0, 1)
        
    if (nic == 1) || !run_parallel
        several_est_results = Vector{GMMResult}(undef, nic)
        for i=1:nic
            several_est_results[i] = fit(i, model, opts)
        end
    else
        several_est_results = pmap( i -> fit(i, model, opts), 1:nic)
    end
    best_result = process_results(several_est_results)

    # Base.show(best_result)
    write(best_result, opts, filename="results.csv")

    # delete all intermediate files with individual iteration results
    if opts.clean_iter 
        print("Deleting intermediate files...")
        rm(opts.path * "__iter__/", force=true, recursive=true)
        println(" Done.")
    end

    return best_result
end

"""
fit function with one initial condition
"""
function fit(idx::Int64, model::GMMProb, opts::GMMOptions)

    print("...estimation run ", idx, ". ")

    # skip if output file already exists
    if !opts.overwrite && (opts.path != "")
        
        opt_results_from_file = load(opts, "__iter__/results_" * string(idx) * ".csv")
        
        if !isnothing(opt_results_from_file)
            println(" Reading from file.")
            return opt_results_from_file
        end
    end

    # single vector of initial conditions
    theta0 = model.theta0[idx, :]

    # matrix of instruments
    # Z = Matrix(model.data[:, model.z])
    # Zsparse = SparseMatrixCSC(Z)

    # load the data
    gmm_objective_loaded = theta -> gmm_objective(theta, model, debug=opts.debug)

    # optimize
    time_it_took = @elapsed raw_opt_results = Optim.optimize(gmm_objective_loaded, theta0, opts.optim_opts)
    #= 
    summary(res)
    minimizer(res)
    minimum(res)
    iterations(res)
    iteration_limit_reached(res)
    trace(res)
    x_trace(res)
    f_trace(res)
    f_calls(res)
    converged(res)
    =#
    
    opt_results = GMMResult(
        converged = Optim.converged(raw_opt_results),
        theta_hat = Optim.minimizer(raw_opt_results),
        obj_value = Optim.minimum(raw_opt_results),
        iterations = Optim.iterations(raw_opt_results),
        iteration_limit_reached = Optim.iteration_limit_reached(raw_opt_results),
        theta0 = theta0,
        time_it_took = time_it_took,
        idx=idx
    )

    # write intermediate results to file
    if opts.write_iter 
        println(" Done and done writing to file.")
        write(opt_results, opts, subpath="__iter__", filename="results_" * string(idx) * ".csv")
    else
        println(" Done. ")
    end

    return opt_results
end





function process_boot_results(lb::Vector{GMMResult})

    boot_results_allruns = []
    nboot = length(lb)
    for i=1:nboot
        temp_df = copy(lb[i].all_results)
        temp_df[!, :boot_idx] .= i
        push!(boot_results_allruns, temp_df)
    end
    boot_results_allruns = vcat(boot_results_allruns...)
    
    # vcat([b.all_results for b=lb]...)

    mysample = boot_results_allruns.is_optimum .== 1
    boot_results = copy(boot_results_allruns[mysample, :])

    # nparams = length(lb[1].theta_hat)
    # nboot = length(lb)

    # res_table = Matrix{Float64}(undef, nboot, nparams)
    # for i=1:nboot
    #     res_table[i, :] = lb[i].theta_hat
    #     lb[i].all_results[!, :boot_idx] .= i
    # end

    return GMMBootResults(
        all_results = boot_results,
        all_results_allbootruns = boot_results_allruns
    )
end




"""
Bayesian bootstrap
"""
function bboot(
    model::GMMProb; 
    setup_fn::Union{Function, Nothing}=nothing, 
    nboot=100, 
    cluster_var=nothing, 
    run_parallel=true,
    opts::GMMOptions=GMMOptions())

    if opts.path != ""
        bootpath = opts.path * "__boot__"
        isdir(bootpath) || mkdir(bootpath)
    end

    if !isnothing(cluster_var)
        cluster_values = unique(model.data[:, cluster_var])

        ### ___idx_cluster___ has the index in the cluster_values vector of this row's value        
            # drop column if already in the df
            ("___idx_cluster___" in names(model.data)) && select!(model.data, Not("___idx_cluster___"))

            # join
            temp_df = DataFrame(string(cluster_var) => cluster_values, "___idx_cluster___" => 1:length(cluster_values))
            leftjoin!(model.data, temp_df, on=cluster_var)
    else
        cluster_values=nothing
    end

    #         
    if !run_parallel
        list_of_boot_results = Vector{GMMResult}(undef, nboot)
        for i=1:nboot
            list_of_boot_results[i] = bboot(i, model, opts, setup_fn=setup_fn, cluster_var=cluster_var)
        end
    else
        list_of_boot_results = pmap( 
            i -> bboot(i, model, opts, 
                    setup_fn=setup_fn,
                    cluster_var=cluster_var, 
                    cluster_values=cluster_values), 
            1:nboot)
    end

    boot_results = process_boot_results(list_of_boot_results)

    write(boot_results, opts)

    # delete all intermediate files with individual iteration results
    if opts.clean_iter 
        print("Deleting individual boot files...")
        rm(opts.path * "__boot__/", force=true, recursive=true)
        println(" Done.")
    end

    return boot_results
end

function bboot(
    idx::Int64, 
    model::GMMProb, 
    opts::GMMOptions; 
    setup_fn::Union{Function, Nothing}=nothing,
    cluster_var=nothing, 
    cluster_values)

    println("bootstrap run ", idx)
    
    if isnothing(cluster_var)
        model.weights = rand(Dirichlet(nrow(model.data), 1.0))
    else
        cluster_level_weights = rand(Dirichlet(length(cluster_values), 1.0))

        # one step "join" to get the weight for the appropriate cluster
        model.weights .= cluster_level_weights[model.data.___idx_cluster___]
    end

    # normalizing weights is important for numerical precision
    model.weights = model.weights ./ mean(model.weights)

    # path for saving results
    new_opts = copy(opts)
    new_opts.path *= "__boot__/boot_" * string(idx) * "_"

    return fit(model, setup_fn=setup_fn, run_parallel=false, opts=new_opts)
end







### Table
function coef(r::GMMResult)

    df = r.all_results
    mysample = df.is_optimum .== 1
    theta_hat = df[mysample, :theta_hat]
    theta_hat = parse_vector(theta_hat[1])
    
    return theta_hat
end


# Returns a matrix with all bootstrap estimates (for computing CIs of other stats)
function theta_hat_boot(rb::Union{GMMBootResults, GMMResult})
    x = parse_vector.(rb.all_results.theta_hat)
    x = hcat(x...) |> Transpose |> Matrix

    return x
end

# Returns confidence intervals (95%)
function cis(rb::GMMBootResults; ci_levels=[2.5, 97.5])

    nparams = length(rb.all_results[1, :theta_hat])

    theta_hat_boot = theta_hat_boot(rb)

    cis = []
    for i=1:nparams
        cil, cih = percentile(theta_hat_boot[:, i], ci_levels)
        push!(cis, (cil, cih))
    end
    
    return cis
end

# Returns standard errors (SD of bootstrap estimates)
function stderr(rb::GMMBootResults)

    nparams = length(rb.all_results[1, :theta_hat])

    theta_hat_boot = theta_hat_boot(rb)

    stderrors = zeros(nparams)
    for i=1:nparams
        stderrors[i] = std(theta_hat_boot[:, i])
    end
    
    return stderrors
end


# struct GMMResults <: RegressionModel
#     coef::Vector{Float64}   # Vector of coefficients
#     vcov::Matrix{Float64}   # Covariance matrix
#     vcov_type::CovarianceEstimator
#     nclusters::Union{NamedTuple, Nothing}

#     esample::BitVector      # Is the row of the original dataframe part of the estimation sample?
#     residuals::Union{AbstractVector, Nothing}
#     fe::DataFrame
#     fekeys::Vector{Symbol}


#     coefnames::Vector       # Name of coefficients
#     responsename::Union{String, Symbol} # Name of dependent variable
#     formula::FormulaTerm        # Original formula
#     formula_schema::FormulaTerm # Schema for predict
#     contrasts::Dict

#     nobs::Int64             # Number of observations
#     dof::Int64              # Number parameters estimated - has_intercept. Used for p-value of F-stat.
#     dof_fes::Int64          # Number of fixed effects
#     dof_residual::Int64     # dof used for t-test and p-value of F-stat. nobs - degrees of freedoms with simple std
#     rss::Float64            # Sum of squared residuals
#     tss::Float64            # Total sum of squares

#     F::Float64              # F statistics
#     p::Float64              # p value for the F statistics

#     # for FE
#     iterations::Int         # Number of iterations
#     converged::Bool         # Has the demeaning algorithm converged?
#     r2_within::Union{Float64, Nothing}      # within r2 (with fixed effect

#     # for IV
#     F_kp::Union{Float64, Nothing}           # First Stage F statistics KP
#     p_kp::Union{Float64, Nothing}           # First Stage p value KP
# end

# has_iv(m::FixedEffectModel) = m.F_kp !== nothing
# has_fe(m::FixedEffectModel) = has_fe(m.formula)



# StatsAPI.coef(m::FixedEffectModel) = m.coef
# StatsAPI.coefnames(m::FixedEffectModel) = m.coefnames
# StatsAPI.responsename(m::FixedEffectModel) = m.responsename
# StatsAPI.vcov(m::FixedEffectModel) = m.vcov
# StatsAPI.nobs(m::FixedEffectModel) = m.nobs
# StatsAPI.dof(m::FixedEffectModel) = m.dof
# StatsAPI.dof_residual(m::FixedEffectModel) = m.dof_residual
# StatsAPI.r2(m::FixedEffectModel) = r2(m, :devianceratio)
# StatsAPI.islinear(m::FixedEffectModel) = true
# StatsAPI.deviance(m::FixedEffectModel) = rss(m)
# StatsAPI.nulldeviance(m::FixedEffectModel) = m.tss
# StatsAPI.rss(m::FixedEffectModel) = m.rss
# StatsAPI.mss(m::FixedEffectModel) = nulldeviance(m) - rss(m)
# StatsModels.formula(m::FixedEffectModel) = m.formula_schema
# dof_fes(m::FixedEffectModel) = m.dof_fes