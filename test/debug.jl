#######################################################################

reload("ReverseDiffSource")
reload("Lora") ; m = Lora

fn = :deuivnode
typ = Range
typeof(typ)

:( $(Expr(:call, fn, Expr(:(::), :x, symbol("$typ")) )) )


using Distributions

Bernoulli(0.26)
rand(Bernoulli(.32),5)

logpdf( Bernoulli(0.32), 1 )
logpdf( Bernoulli(0.32), [0,1] )
logpdf( [Bernoulli(0.32), Bernoulli(0.32)] , [0,1] )


logpdf(  )

logpdf2{T<:Distribution}(ds::Array{T}, x::AbstractArray) = map(logpdf, )

methods(logpdf)

#########################################################################
#    testing script for simple examples 
#########################################################################

using Distributions

# generate a random dataset
srand(1)
n = 1000
nbeta = 10 
X = [ones(n) randn((n, nbeta-1))] 
beta0 = randn((nbeta,))
Y = rand(n) .< ( 1 ./ (1 .+ exp(X * beta0))) 

# define model
ex = quote
	vars ~ Normal(0, 1.0)  
	prob = 1 ./ (1. .+ exp(X * vars)) 
	Y ~ Bernoulli(prob)
end


mod = m.model(ex, vars=zeros(nbeta), gradient=true)

mod.eval(zeros(nbeta))
mod.evalg(zeros(nbeta))

names(mod)

m.model(ex, vars=zeros(nbeta), gradient=true, debug=true)
m.generateModelFunction(ex, vars=zeros(nbeta), gradient=true, debug=true)

# different samplers
res = m.run(m * m.MH(0.05) * m.SerialMC(100:1000))
res = run(m * HMC(2, 0.1) * SerialMC(100:1000))
res = run(m * NUTS() * SerialMC(100:1000))
res = run(m * MALA(0.001) * SerialMC(100:1000))
# TODO : add other samplers here

# different syntax
res = run(m, RWM(), SerialMC(steps=1000, thinning=10, burnin=0))
res = run(m, HMC(2,0.1), SerialMC(thinning=10, burnin=0))
res = run(m, HMC(2,0.1), SerialMC(burnin=20))


###############  
function generateModelFunction(model::Expr; gradient=false, debug=false, init...)
	# model, gradient, debug, init = ex, true, false, [(:vars, zeros(nbeta))]

	model.head != :block && (model = Expr(:block, model))  # enclose in block if needed
	length(model.args)==0 && error("model should have at least 1 statement")

	vsize, pmap, vinit = m.modelVars(;init...) # model param info

	model = m.translate(model) # rewrite ~ statements
	model = Expr(:block, [ :($(m.ACC_SYM) = LLAcc(0.)), # add log-lik accumulator initialization
		                   model.args, 
		                   # :( $ACC_SYM = $(Expr(:., ACC_SYM, Expr(:quote, :val)) ) )]... )
		                   :( $(Expr(:., m.ACC_SYM, Expr(:quote, :val)) ) )]... )


g  = m.ReverseDiffSource.drules[(logpdf,1)][(AbstractArray{Bernoulli}, AbstractArray)][1]
ss = m.ReverseDiffSource.drules[(logpdf,1)][(AbstractArray{Bernoulli}, AbstractArray)][2]

g  = m.ReverseDiffSource.drules[(logpdf,2)][(AbstractArray{Bernoulli}, AbstractArray)][1]
ss = m.ReverseDiffSource.drules[(logpdf,1)][(AbstractArray{Bernoulli}, AbstractArray)][2]


	dmodel = m.rdiff(model, vars=zeros(10))
quote 
    _tmp1 = 0.0
    _tmp2 = Lora.LLAcc(0.0)
    _tmp3 = Distributions.Normal(0.0,1.0)
    _tmp4 = X * vars
    _tmp5 = size(vars)
    _tmp6 = logpdf(_tmp3,vars)
    _tmp7 = exp(_tmp4)
    _tmp8 = zeros(size(Y))
    _tmp9 = zeros(_tmp5)
    _tmp10 = 1.0 .+ _tmp7
    _tmp11 = size(_tmp6)
    _tmp1 =  1.0
    _tmp2 = _tmp2 + _tmp6
    _tmp12 = 1.0 ./ _tmp10
    _tmp13 = _tmp1
    _tmp14 = Distributions.Bernoulli(_tmp12)
    _tmp1 = 0.0
    _tmp15 = logpdf(_tmp14,Y)
    _tmp16 = size(_tmp15)
    _tmp17 = fill(0.0,_tmp11) + fill(_tmp1,_tmp11)
    _tmp2 = _tmp2 + _tmp15
    for i = 1.0:length(vars)
        _tmp9[i] = ((_tmp3.μ - vars[i]) / (_tmp3.σ * _tmp3.σ)) * _tmp17[i]
    end
    _tmp18 = fill(0.0,_tmp16) + fill(_tmp13,_tmp16)
    for i = 1.0:length(Y)
        _tmp8[i] = (1.0 / ((_tmp14[i].p - 1.0) + Y[i])) * _tmp18[i]
    end
    _tmp19 = fill(0.0,size(_tmp14)) + _tmp8
    _tmp20 = zeros(size(_tmp19))
    for i = 1.0:length(_tmp19)
        _tmp20[i] = _tmp19[i]
    end
    (_tmp2.val,((fill(0.0,_tmp5) + _tmp9) + X' * (fill(0.0,size(_tmp4)) + _tmp7 .* (fill(0.0,size(_tmp7)) + (fill(0.0,size(_tmp10)) + -((fill(0.0,size(_tmp12)) + _tmp20)) ./ (_tmp10 .* _tmp10)))),))
end

	vars = zeros(10)
	m.eval( dmodel )

	## build function expression
	if gradient  # case with gradient
		head, body, outsym = ReverseDiffSource.reversediff(model, 
			                                               rv, false, Lora; 
			                                               init...)

		body = [ m.vec2var(;init...),  # assigments beta vector -> model parameter vars
		         body.args,
		         :(($outsym, $(m.var2vec(;init...))))]

		# enclose in a try block
		body = Expr(:try, Expr(:block, body...),
				          :e, 
				          quote 
				          	if isa(e, OutOfSupportError)
				          		return(-Inf, zero($PARAM_SYM))
				          	else
				          		rethrow(e)
				          	end
				          end)

	else  # case without gradient
		head, body, outsym = ReverseDiffSource.reversediff(model, 
			                                               rv, true, Lora; 
			                                               init...)

		body = [ vec2var(;init...),  # assigments beta vector -> model parameter vars
		         body.args,
		         outsym ]

		# enclose in a try block
		body = Expr(:try, Expr(:block, body...),
				          :e, 
				          quote 
				          	if isa(e, OutOfSupportError)
				          		return(-Inf)
				          	else
				          		rethrow(e)
				          	end
				          end)

	end

	# build and evaluate the let block containing the function and var declarations
	fn = gensym("ll")
	body = Expr(:function, Expr(:call, fn, :($PARAM_SYM::Vector{Float64})),	Expr(:block, body) )
	body = Expr(:let, Expr(:block, :(global $fn), head.args..., body))

	# println("#############\n$body\n############")

	debug ? body : (eval(body) ; (eval(fn), vsize, pmap, vinit) )
end

### README examples 

mymodel1 = model(v-> -dot(v,v), init=ones(3))
mymodel2 = model(v-> -dot(v,v), grad=v->-2v, init=ones(3))   

modelxpr = quote
    v ~ Normal(0, 1)
end

mymodel3 = model(modelxpr, v=ones(3))
mymodel4 = model(modelxpr, gradient=true, v=ones(3))

mychain = run(mymodel1, RWM(0.1), SerialMC(steps=1000, burnin=100))
mychain = run(mymodel1, RWM(0.1), SerialMC(steps=1000, burnin=100, thinning=5))
mychain = run(mymodel1, RWM(0.1), SerialMC(101:5:1000))
mychain1 = run(mymodel1 * RWM(0.1) * SerialMC(101:5:1000))

mychain2 = run(mymodel2, HMC(0.75), SerialMC(steps=10000, burnin=1000))

acceptance(mychain2)

# describe(mychain2)

ess(mychain2)

actime(mychain2)

# var(mychain2)
# var(mychain2, vtype=:iid)
# var(mychain2, vtype=:ipse)
# var(mychain2, vtype=:bm)

mychain1 = resume(mychain1, steps=10000)

@test_throws ErrorException run(mymodel3 * MALA(0.1) * SerialMC(1:1000))

run(mymodel4 * MALA(0.1) * SerialMC(1:1000))

mychain = run(mymodel2 * [RWM(0.1), MALA(0.1), HMC(3,0.1)] * SerialMC(steps=1000)) 
mychain[2].samples

mychain = run(mymodel2 * [HMC(i,0.1) for i in 1:5] * SerialMC(steps=1000))

nmod = 10
mods = Array(MCMCLikModel, nmod)
sts = logspace(1, -1, nmod)
for i in 1:nmod
  m = quote
    y = abs(x)
    y ~ Normal(1, $(sts[i]))
  end
  mods[i] = model(m, x=0)
end

targets = MCMCTask[mods[i] * RWM(sts[i]) * SeqMC(steps=10, burnin=0) for i in 1:nmod]
particles = [[randn()] for i in 1:1000]

mychain3 = run(targets, particles=particles)

# mychain4 = wsample(mychain3.samples, mychain3.diagnostics["weigths"], 1000)
# mean(mychain4)
