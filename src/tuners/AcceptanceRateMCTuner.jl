### Auxiliary functions used as scores for penalising deviation of observed from target acceptance rate

## logistic_rate_score

# logistic_rate_score uses the logistic function to scale the acceptance rate by a factor ranging from 0 to 2
# In other words, it allows to nearly eliminate or double the rate depending on its observed value
# k gives the curve's steepness. For larger k, the curve becomes more steep

logistic_rate_score(x::Real, k::Real=7.) = logistic(x, 2., k, 0., 0.)

## erf_rate_score

# erf_rate_score uses the error function (erf) to scale the acceptance rate by a factor ranging from 0 to 2
# In other words, it allows to nearly eliminate or double the rate depending on its observed value
# k gives the curve's steepness. For larger k, the curve becomes more steep

erf_rate_score(x::Real, k::Real=3.) = erf(k*x)+1

### AcceptanceRateMCTuner

# AcceptanceRateMCTuner tunes empirically on the basis of the discrepancy between observed and target acceptance rate
# This discrepancy is pernalised via a score function set by the user
# The default score function is a stretched logistic map

immutable AcceptanceRateMCTuner <: MCTuner
  targetrate::Float64 # Target acceptance rate
  score::Function # Score function for penalising discrepancy between observed and target acceptance rate
  period::Int # Tuning period over which acceptance rate is computed
  verbose::Bool # If verbose=false then the tuner is silent, else it is verbose

  function AcceptanceRateMCTuner(targetrate::Float64, score::Function, period::Int, verbose::Bool)
    @assert 0 < targetrate < 1 "Target acceptance rate should be between 0 and 1"
    @assert period > 0 "Tuning period should be positive"
    new(targetrate, score, period, verbose)
  end
end

AcceptanceRateMCTuner(
  targetrate::Float64;
  score::Function=logistic_rate_score,
  period::Int=100,
  verbose::Bool=false
) =
  AcceptanceRateMCTuner(targetrate, score, period, verbose)

tuner_state(tuner::AcceptanceRateMCTuner) = BasicMCTune()

tune!(tune::BasicMCTune, tuner::AcceptanceRateMCTuner) = (tune.rate *= tuner.score(tune.rate-tuner.targetrate))
