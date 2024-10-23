"""
    ParameterObjects

All the logic for the individual parameter class
"""
module ParameterObjects

    using OrderedCollections


    export AbstractParameter, Constant, Parameter, Expression, IndependentVariable
    export validate, depends_on, _update_params_from_vect!
    export PARAMETERS

    """
    Parameters are the elemental components of the `LMfit` package.

    In order to improve my Julia programming, I am going to define the different kinds of possible parameters 
    in terms of a base class
    """
    abstract type AbstractParameter end
    AbstractParameter(p::AbstractParameter) = deepcopy(p)

    function AbstractParameter(name; kwargs...) # dispatch to the desired type of parameter

        if get(kwargs, :independent, false) == true
            return IndependentVariable(name;)
        else
            return Parameter(name; kwargs...)
        end
    end
    validate(p::AbstractParameter) = nothing
    depends_on(p::AbstractParameter) = Set{Symbol}()
    Base.length(p::AbstractParameter) = length(p.value)

    function Base.show(io::IO, p::AbstractParameter) 
        println(io, String(p))
    end

    """
    Constant
    """
    mutable struct Constant{T} <: AbstractParameter
        name::Symbol
        value::T
    end
    Constant(name::Symbol; value=NaN) = Constant(name, value)

    Base.String(p::Constant) = "Constant: name=$(p.name),\tvalue=$(p.value)"


    """
    Parameter

    This is the elemental component of the `LMfit` package.

    The type T has to support Nan, Inf, and -Inf
    """
    mutable struct Parameter{T} <: AbstractParameter
        name::Symbol
        value::T
        min::T
        max::T
    end
    function Parameter(name::Symbol; value=NaN, min=nothing, max=nothing)
        if max === nothing
            max = value .* (Inf)
        end

        if min === nothing
            min = value .* (-Inf)
        end

        Parameter(name, value, min, max)
    end
    function Parameter(name::Symbol, arg)
        println("Parameter: name=$(name),\targ=$(arg)")
    end

    Base.String(p::Parameter) = "Parameter: name=$(p.name),\tvalue=$(p.value),\tmin=$(p.min),\tmax=$(p.max)"

    function validate(p::Parameter)
        if length(p) != length(p.min) || length(p) != length(p.max)
            error("item $(p.name): length of all values and limit variables must be the same")
        end

        if any(min > max for (min, max) in zip(p.min, p.max))
            error("item $(p.name): p.min = $(p.min) must be less than p.max = $(p.max)")
        end

        if any((value > max || value < min) for (min, max, value) in zip(p.min, p.max, p.value))
            error("item $(p.name): p.value = $(p.value) must be between p.min=$(p.min) and p.max=$(p.max)")
        end
        true
    end


    """
    Expression

    This is the elemental component of the `LMfit` package.

    The type T has to support Nan, Inf, and -Inf
    """
    mutable struct Expression{T} <: AbstractParameter
        name::Symbol
        value::T
        expr::Expr
    end
    Expression(name::Symbol; expr=:(), value=NaN) = return Expression(name, value, expr)

    Base.String(p::Expression) = "Expression: name=$(p.name),\tvalue=$(p.value),\texpr=$(p.expr)"

    depends_on(p::Expression) = _get_symbols(p.expr)
  
    """
    IndependentVariable

    Used to identify independent variables
    """
    mutable struct IndependentVariable <: AbstractParameter
        name::Symbol
    end
    function Base.show(io::IO, p::IndependentVariable) 
        println(io, String(p))
    end
    Base.String(p::IndependentVariable) = "IndependentVariable: name=$(p.name)"

    function _get_symbols(ex)
        list = []
        walk!(list) = ex -> begin
           ex isa Symbol && push!(list, ex)
           ex isa Expr && ex.head == :call && map(walk!(list), ex.args[2:end])
           list
        end
        Set{Symbol}(walk!([])(ex))
    end

    # Annoying that I have to define this at the end of the module
    PARAMETERS = Dict(
        :constant=>Constant, 
        :expression=>Expression, 
        :parameter=>Parameter
        )

    # Conversion tools
    Constant(p::Parameter) = Constant(p.name, p.value)
    Constant(p::Expression) = Constant(p.name, p.value)

    Parameter(p::Constant; kwargs...) = Parameter(p.name; value=p.value, kwargs...)
    Parameter(p::Expression; kwargs...) = Parameter(p.name; value=p.value, min=p.min, max=p.max, kwargs...)

    Expression(p::Constant; kwargs...) = Expression(p.name; value=p.value, min=p.min, max=p.max, kwargs...)
    Expression(p::Parameter; kwargs...) = Expression(p.name; value=p.value, kwargs...)

    #=
    .########.....###....########.....###....##.....##.########.########.########.########...######.
    .##.....##...##.##...##.....##...##.##...###...###.##..........##....##.......##.....##.##....##
    .##.....##..##...##..##.....##..##...##..####.####.##..........##....##.......##.....##.##......
    .########..##.....##.########..##.....##.##.###.##.######......##....######...########...######.
    .##........#########.##...##...#########.##.....##.##..........##....##.......##...##.........##
    .##........##.....##.##....##..##.....##.##.....##.##..........##....##.......##....##..##....##
    .##........##.....##.##.....##.##.....##.##.....##.########....##....########.##.....##..######.
    =#

    struct Parameters
        parameters::OrderedDict{Symbol, AbstractParameter}
    end
    Parameters(ps::Parameters) = deepcopy(ps)
    Parameters() = Parameters(OrderedDict{Symbol, Parameter}())
    Parameters(args...; kwargs...) = add!(Parameters(), args...; kwargs...)

    #
    # New methods for existing Base functions
    #

    function Base.getindex(ps::Parameters, indices...)
        ps.parameters[indices...]
    end
    Base.iterate(ps::Parameters) = iterate(ps.parameters)
    Base.iterate(ps::Parameters, state) = iterate(ps.parameters, state)
    Base.keys(ps::Parameters) = keys(ps.parameters)
    Base.length(ps::Parameters) = length(ps.parameters)
    Base.values(ps::Parameters) = values(ps.parameters)
    Base.setindex!(ps::Parameters, value, key) = setindex!(ps.parameters, value, key)

    function Base.show(io::IO, ps::Parameters)
        println(io, "Parameters:")
        for p in values(ps.parameters)
            println(io, "\t$(String(p))")
        end
    end

    # New methods

    function add!(ps::Parameters, p::AbstractParameter)
        ps.parameters[p.name] = p
        ps
    end
    function add!(ps::Parameters, pvec::Vector{AbstractParameter})
        for p in pvec
            add!(ps, p)
        end
        ps
    end
    add!(ps::Parameters, name::Symbol, parameter_type::Symbol, args...; kwargs...) = add!(ps, PARAMETERS[parameter_type](name, args...; kwargs...))
    function add!(ps::Parameters, name::Symbol, args...; kwargs...)

        kwargs = Dict(kwargs)
        param_type = pop!(kwargs, :param_type, :parameter) # default to a parameter, otherwise the keyword argument :param_type will be used
        add!(ps::Parameters, name::Symbol, param_type, args...; kwargs...) 
    end
    """
        depends_on

    find all dependencies between parameters
    """
    depends_on(ps::Parameters) = Dict(k=>depends_on(p) for (k, p) in ps)

    """
        validate

    check for error conditions
    """
    function validate(ps::Parameters)
        for (name, p) in ps
            if name != p.name
                error("item $(name): Parameters name-key must match name-field the associated record")
            end

            validate(p)
        end
        return true
    end

    """
        find_dependencies!(ps::Parameters)

    This is a key part of the logic of this package.  It will iterate over the parameters to see if they are
    fully determined, and to check for error conditions such as circular dependencies.

    It will then resort the parameters in the order that they need to be resolved if there are no errors
    """
    function find_dependencies!(ps::Parameters)

        # Find dependencies
        dependencies = depends_on(ps)

        sorted_parameters = empty(ps.parameters) # create an empty version of ps.parameters

        resolved_one = true
        while resolved_one 
            resolved_one = false

            # find resolved dependencies
            for (name, dep) in dependencies
                if isempty(dep)
                    sorted_parameters[name] = ps[name]
                    delete!(dependencies, name)
                    resolved_one = true
                end
            end

            # remove resolved variables from depends_on sets
            for dep in values(dependencies)
                for sorted in values(sorted_parameters)
                    delete!(dep, sorted.name)
                end
            end
        end

        if !isempty(dependencies)
            error("Circular dependencies detected")
        end

        empty!(ps.parameters)
        for (name, p) in sorted_parameters
            ps.parameters[name] = p
        end

        return ps
    end

    """
    Creates a function that evaluates a vector of varied parameters and returns a vector of all the parameters
    """
    function resolve_parameters(ps::Parameters)
        
        inputs = [p for p in values(ps) if typeof(p) <: Parameter]
        constants = [p for p in values(ps) if typeof(p) <: Constant]
        expressions = [p for p in values(ps) if typeof(p) <: Expression]

        # we take a vector of parameters
        prog = "(params) -> begin\n"

        # we unpack the adjustable parameters into their associated variables
        i = 1
        for p in inputs
            len = length(p)
            line = "   $(p.name) = params[$(i):$(i+len-1)]\n"
            prog *= line
            i += len
        end
        prog *= "\n"

        # we unpack the constant parameters into their associated variables
        lines = ["   $(p.name) = $(p.value)\n" for (i, p) in enumerate(constants)]
        prog *= join(lines)
        prog *= "\n"

        # we unpack the expression parameters into their associated variables
        lines = ["   $(p.name) = @. $(string(p.expr))\n" for (i, p) in enumerate(expressions)]
        prog *= join(lines)
        prog *= "\n"

        # we pack these up into a single array
        prog *= "   result::Vector{Float64} = vcat("
        lines = ["$(p.name), " for (_, p) in enumerate(values(ps))]
        prog *= join(lines)
        prog *= ")\n"
        # prog *= "println(result)\n"
        
        prog *= "   return result\n" 
        prog *= "end"

        # println(prog)

        body = Meta.parse(prog)

        eval(body)
    end

    """
        _update_params_from_vect!(ps::Parameters, params_vect)
    
    Update parameters from the entries provided in params_vect

    This assumes that the parameters are ordered in the same way as the params_vect,
    and that total lengths are compatable
    """
    function _update_params_from_vect!(ps::Parameters, params_vect)
        index = 1
        for p in values(ps)
            if typeof(p.value) <: Number
                len = 1
                p.value = params_vect[index]
            else
                len = length(p)
                p.value = params_vect[index:index+len-1]
            end
            index += len
        end
        ps
    end

end