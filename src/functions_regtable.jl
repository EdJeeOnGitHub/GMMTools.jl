
Base.@kwdef struct GMMModel <: RegressionModel
    coef::Vector{Float64}   # Vector of coefficients
    vcov::Matrix{Float64}   # Covariance matrix
    vcov_type::CovarianceEstimator
    nclusters::Union{NamedTuple, Nothing} = nothing

    esample::BitVector      # Is the row of the original dataframe part of the estimation sample?
    residuals::Union{AbstractVector, Nothing} = nothing
    fe::DataFrame
    fekeys::Vector{Symbol}


    coefnames::Vector       # Name of coefficients
    responsename::Union{String, Symbol} # Name of dependent variable
    # formula::FormulaTerm        # Original formula
    # formula_schema::FormulaTerm # Schema for predict
    contrasts::Dict

    nobs::Int64             # Number of observations
    dof::Int64              # Number parameters estimated - has_intercept. Used for p-value of F-stat.
    dof_fes::Int64          # Number of fixed effects
    dof_residual::Int64     # dof used for t-test and p-value of F-stat. nobs - degrees of freedoms with simple std
    rss::Float64            # Sum of squared residuals
    tss::Float64            # Total sum of squares

    F::Float64              # F statistics
    p::Float64              # p value for the F statistics

    # for FE
    iterations::Int         # Number of iterations
    converged::Bool         # Has the demeaning algorithm converged?
    r2_within::Union{Float64, Nothing} = nothing      # within r2 (with fixed effect

    # for IV
    F_kp::Union{Float64, Nothing} = nothing           # First Stage F statistics KP
    p_kp::Union{Float64, Nothing} = nothing           # First Stage p value KP
end


has_iv(m::GMMModel) = m.F_kp !== nothing
has_fe(m::GMMModel) = false

# RegressionTables.get_coefname(x::Tuple{Vararg{Term}}) = RegressionTables.get_coefname.(x)
# RegressionTables.replace_name(x::Tuple{Vararg{Any}}, a::Dict{String, String}, b::Dict{String, String}) = [RegressionTables.replace_name(x[i], a, b) for i=1:length(x)]

RegressionTables.formula(m::GMMModel) = term(m.responsename) ~ sum(term.(String.(m.coefnames)))

StatsAPI.coef(m::GMMModel) = m.coef
StatsAPI.coefnames(m::GMMModel) = m.coefnames
StatsAPI.responsename(m::GMMModel) = m.responsename
StatsAPI.vcov(m::GMMModel) = m.vcov
StatsAPI.nobs(m::GMMModel) = m.nobs
StatsAPI.dof(m::GMMModel) = m.dof
StatsAPI.dof_residual(m::GMMModel) = m.dof_residual
StatsAPI.r2(m::GMMModel) = r2(m, :devianceratio)
StatsAPI.islinear(m::GMMModel) = true
StatsAPI.deviance(m::GMMModel) = rss(m)
StatsAPI.nulldeviance(m::GMMModel) = m.tss
StatsAPI.rss(m::GMMModel) = m.rss
StatsAPI.mss(m::GMMModel) = nulldeviance(m) - rss(m)
# StatsModels.formula(m::GMMResultTable) = m.formula_schema
dof_fes(m::GMMModel) = m.dof_fes

function vcov(r::GMMFit)
    if isnothing(r.vcov)
        nparams = length(r.theta_hat)
        return zeros(nparams, nparams)
    else
        return r.vcov[:V]
    end
end

function vcov_method(r::GMMFit)
    if isnothing(r.vcov)
        return Vcov.simple()
    else
        return r.vcov[:method]
    end
end

function GMMModel(r::GMMFit)
    
    nobs = r.N

    if isnothing(r.vcov)
        @error "Cannot print table. No vcov estimated yet"
        error("Cannot print table. No vcov estimated yet")
    end

    if isnothing(r.theta_names)
        r.theta_names = ["theta_$i" for i=1:length(r.theta_hat)]
    end

    GMMModel(
        coef = r.theta_hat,
        vcov = vcov(r),
        vcov_type=vcov_method(r),
        esample=[],
        fe=DataFrame(),
        fekeys=[],
        coefnames=r.theta_names,
        responsename="a",
        # formula::FormulaTerm        # Original formula
        # formula_schema::FormulaTerm # Schema for predict
        contrasts=Dict(),
        nobs=nobs,
        dof=nobs,
        dof_fes=1,
        dof_residual=nobs, # TODO: needs adjustment for parameters (!?)
        rss=0.00,
        tss=0.00,
        F=0.0,
        p=0.0,
        iterations=5, 
        converged=true)         
end

# TODO: integrate better with RegressionModels, allow mixed inputs etc. Should be easy.
function regtable(r::GMMFit)
    RegressionTables.regtable(GMMModel(r), render = AsciiTable())
end

        # labels = Dict("__LABEL_ESTIMATOR_OLS__" => "GMM"), 


### Table
# function coef(r::GMMResult)

#     df = r.all_results
#     mysample = df.is_optimum .== 1
#     theta_hat = df[mysample, :theta_hat]
#     theta_hat = parse_vector(theta_hat[1])
    
#     return theta_hat
# end

# Returns a matrix with all bootstrap estimates (for computing CIs of other stats)
# function theta_hat_boot(rb::Union{GMMBootResults, GMMResult})
#     x = parse_vector.(rb.all_results.theta_hat)
#     x = hcat(x...) |> Transpose |> Matrix

#     return x
# end

# # Returns confidence intervals (95%)
# function cis(rb::GMMBootResults; ci_levels=[2.5, 97.5])

#     nparams = length(rb.all_results[1, :theta_hat])

#     theta_hat_boot = theta_hat_boot(rb)

#     cis = []
#     for i=1:nparams
#         cil, cih = percentile(theta_hat_boot[:, i], ci_levels)
#         push!(cis, (cil, cih))
#     end
    
#     return cis
# end

# Returns standard errors (SD of bootstrap estimates)
# function stderr(rb::GMMBootResults)

#     nparams = length(rb.all_results[1, :theta_hat])

#     theta_hat_boot = theta_hat_boot(rb)

#     stderrors = zeros(nparams)
#     for i=1:nparams
#         stderrors[i] = std(theta_hat_boot[:, i])
#     end
    
#     return stderrors
# end
