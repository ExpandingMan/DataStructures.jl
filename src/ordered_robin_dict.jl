const ALLOWABLE_USELESS_GROWTH = 0.25

"""
    OrderedRobinDict([itr])

`OrderedRobinDict{K,V}()` constructs a ordered dictionary with keys of type `K` and values of type `V`.
It takes advantage of `RobinDict` in maintaining the order of the keys. 
Given a single iterable argument, constructs a [`OrderedRobinDict`](@ref) whose key-value pairs 
are taken from 2-tuples `(key,value)` generated by the argument.


# Examples
```jldoctest
julia> OrderedRobinDict([("A", 1), ("B", 2)])
OrderedRobinDict{String,Int64} with 2 entries:
  "A" => 1
  "B" => 2
```

Alternatively, a sequence of pair arguments may be passed.

```jldoctest
julia> OrderedRobinDict("A"=>1, "B"=>2)
OrderedRobinDict{String,Int64} with 2 entries:
  "A" => 1
  "B" => 2
```
"""
mutable struct OrderedRobinDict{K,V} <: AbstractDict{K,V}
    dict::RobinDict{K, Int32} 
    keys::Vector{K}
    vals::Vector{V}
    count::Int32

    function OrderedRobinDict{K, V}() where {K, V}
        new{K, V}(RobinDict{K, Int32}(), Vector{K}(), Vector{V}(), 0)
    end

    function OrderedRobinDict{K, V}(d::OrderedRobinDict{K, V}) where {K, V}
        new{K, V}(copy(d.dict), copy(d.keys), copy(d.vals), d.count)
    end

    function OrderedRobinDict{K,V}(kv) where {K, V}
        h = OrderedRobinDict{K,V}()
        for (k,v) in kv
            h[k] = v
        end
        return h
    end
    OrderedRobinDict{K,V}(p::Pair) where {K,V} = setindex!(OrderedRobinDict{K,V}(), p.second, p.first)
    function OrderedRobinDict{K,V}(ps::Pair...) where V where K
        h = OrderedRobinDict{K,V}()
        sizehint!(h, length(ps))
        for p in ps
            h[p.first] = p.second
        end
        return h
    end
end

OrderedRobinDict() = OrderedRobinDict{Any,Any}()
OrderedRobinDict(kv::Tuple{}) = OrderedRobinDict()
copy(d::OrderedRobinDict) = OrderedRobinDict(d)
empty(d::OrderedRobinDict, ::Type{K}, ::Type{V}) where {K, V} = OrderedRobinDict{K, V}()

OrderedRobinDict(ps::Pair{K,V}...) where {K,V} = OrderedRobinDict{K,V}(ps)
OrderedRobinDict(ps::Pair...)                  = OrderedRobinDict(ps)

OrderedRobinDict(d::AbstractDict{K, V}) where {K, V} = OrderedRobinDict{K, V}(d)

function OrderedRobinDict(kv)
    try
        return dict_with_eltype((K, V) -> OrderedRobinDict{K, V}, kv, eltype(kv))
    catch e
        if !isiterable(typeof(kv)) || !all(x -> isa(x, Union{Tuple,Pair}), kv)
            !all(x->isa(x,Union{Tuple,Pair}),kv)
            throw(ArgumentError("OrderedRobinDict(kv): kv needs to be an iterator of tuples or pairs"))
        else
            rethrow(e)
        end
    end
end

empty(d::OrderedRobinDict{K,V}) where {K,V} = OrderedRobinDict{K,V}()

length(d::Union{RobinDict, OrderedRobinDict}) = d.count
isempty(d::Union{RobinDict, OrderedRobinDict}) = (length(d) == 0)

"""
    empty!(collection) -> collection

Remove all elements from a `collection`.

# Examples
```jldoctest
julia> A = OrderedRobinDict("a" => 1, "b" => 2)
OrderedRobinDict{String,Int64} with 2 entries:
  "a" => 1
  "b" => 2

julia> empty!(A);

julia> A
OrderedRobinDict{String,Int64} with 0 entries
```
"""
function empty!(h::OrderedRobinDict{K,V}) where {K, V}
    empty!(h.dict)
    empty!(h.keys)
    empty!(h.vals)
    h.count = 0
    return h
end

function _setindex!(h::OrderedRobinDict, v, key)
    hk, hv = h.keys, h.vals
    push!(hk, key)
    push!(hv, v)
    nk = length(hk)
    @inbounds h.dict[key] = Int32(nk)
    h.count += 1
end

function setindex!(h::OrderedRobinDict{K, V}, v0, key0) where {K,V}
    key = convert(K, key0)
    v = convert(V, v0)
    index = get(h.dict, key, -2)

    if index < 0
        _setindex!(h, v0, key0)
    else
        @assert haskey(h, key0)
        @inbounds orig_v = h.vals[index]
        (orig_v != v0) && (@inbounds h.vals[index] = v0)
    end

    check_for_rehash(h) && rehash!(h)

    return h
end

# rehash when there are ALLOWABLE_USELESS_GROWTH %
# tombstones, or non-mirrored entries in the dictionary
function check_for_rehash(h::OrderedRobinDict)
    keysl = length(h.keys)
    dictl = length(h)
    return (keysl > (1 + ALLOWABLE_USELESS_GROWTH)*dictl)
end

function rehash!(h::OrderedRobinDict{K, V}) where {K, V}
    keys = h.keys
    vals = h.vals
    hk = Vector{K}()
    hv = Vector{V}()
    
    for (idx, (k, v)) in enumerate(zip(keys, vals))
        if get(h.dict, k, -1) == idx
            push!(hk, k)
            push!(hv, v)
        end
    end
    
    h.keys = hk
    h.vals = hv
    
    for (idx, k) in enumerate(h.keys)
        h.dict[k] = idx
    end
    return h
end

function sizehint!(d::OrderedRobinDict, newsz)
    oldsz = length(d)
    # grow at least 25%
    if newsz < (oldsz*5)>>2
        return d
    end
    sizehint!(d.keys, newsz)
    sizehint!(d.vals, newsz)
    sizehint!(d.dict, newsz)
    return d
end

"""
    get!(collection, key, default)

Return the value stored for the given key, or if no mapping for the key is present, store
`key => default`, and return `default`.

# Examples
```jldoctest
julia> d = OrderedRobinDict("a"=>1, "b"=>2, "c"=>3);

julia> get!(d, "a", 5)
1

julia> get!(d, "d", 4)
4

julia> d
OrderedRobinDict{String,Int64} with 4 entries:
  "a" => 1
  "b" => 2
  "c" => 3
  "d" => 4
```
"""
function get!(h::OrderedRobinDict{K,V}, key0, default) where {K,V}
    index = get(h.dict, key0, -2)
    index > 0 && return h.vals[index]
    v = convert(V, default)
    setindex!(h, v, key0)
    return v
end

"""
    get!(f::Function, collection, key)

Return the value stored for the given key, or if no mapping for the key is present, store
`key => f()`, and return `f()`.

This is intended to be called using `do` block syntax:
```julia
get!(dict, key) do
    # default value calculated here
    time()
end
```
"""
function get!(default::Base.Callable, h::OrderedRobinDict{K,V}, key0) where {K,V}
    index = get(h.dict, key0, -2)
    index > 0 && return @inbounds h.vals[index]
    v = convert(V, default())
    setindex!(h, v, key0)
    return v
end

function getindex(h::OrderedRobinDict{K,V}, key) where {K,V}
    index = get(h.dict, key, -1)
    return (index < 0) ? throw(KeyError(key)) : @inbounds h.vals[index]::V
end

"""
    get(collection, key, default)

Return the value stored for the given key, or the given default value if no mapping for the
key is present.

# Examples
```jldoctest
julia> d = OrderedRobinDict("a"=>1, "b"=>2);

julia> get(d, "a", 3)
1

julia> get(d, "c", 3)
3
```
"""
function get(h::OrderedRobinDict{K,V}, key, default) where {K,V}
    index = get(h.dict, key, -1)
    return (index < 0) ? default : @inbounds h.vals[index]::V
end
"""
    get(f::Function, collection, key)

Return the value stored for the given key, or if no mapping for the key is present, return
`f()`.  Use [`get!`](@ref) to also store the default value in the dictionary.

This is intended to be called using `do` block syntax

```julia
get(dict, key) do
    # default value calculated here
    time()
end
```
"""
function get(default::Base.Callable, h::OrderedRobinDict{K,V}, key) where {K,V}
    index = get(h.dict, key, -1)
    return (index < 0) ? default() : @inbounds h.vals[index]::V
end

"""
    haskey(collection, key) -> Bool

Determine whether a collection has a mapping for a given `key`.

# Examples
```jldoctest
julia> D = OrderedRobinDict('a'=>2, 'b'=>3)
OrderedRobinDict{Char,Int64} with 2 entries:
  'a' => 2
  'b' => 3

julia> haskey(D, 'a')
true

julia> haskey(D, 'c')
false
```
"""
haskey(h::OrderedRobinDict, key) = (get(h.dict, key, -2) > 0)
in(key, v::Base.KeySet{K,T}) where {K,T<:OrderedRobinDict{K}} = (get(v.dict, key, -1) >= 0)

"""
    getkey(collection, key, default)

Return the key matching argument `key` if one exists in `collection`, otherwise return `default`.

# Examples
```jldoctest
julia> D = OrderedRobinDict('a'=>2, 'b'=>3)
OrderedRobinDict{Char,Int64} with 2 entries:
  'a' => 2
  'b' => 3

julia> getkey(D, 'a', 1)
'a': ASCII/Unicode U+0061 (category Ll: Letter, lowercase)

julia> getkey(D, 'd', 'a')
'a': ASCII/Unicode U+0061 (category Ll: Letter, lowercase)
```
"""
function getkey(h::OrderedRobinDict{K,V}, key, default) where {K,V}
    index = get(h.dict, key, -1)
    return (index < 0) ? default : h.keys[index]::K
end

Base.@propagate_inbounds isslotfilled(h::OrderedRobinDict, index) = (h.dict[h.keys[index]] == index)

function _pop!(h::OrderedRobinDict, index)
    @inbounds val = h.vals[index]
    _delete!(h, index)
    return val
end

function pop!(h::OrderedRobinDict)
    check_for_rehash(h) && rehash!(h)
    index = length(h.keys)
    while (index > 0)
        isslotfilled(h, index) && break
        index -= 1
    end
    index == 0 && rehash!(h)
    @inbounds key = h.keys[index]
    return key => _pop!(h, index)
end

function pop!(h::OrderedRobinDict, key)
    index = get(h.dict, key, -1)
    (index > 0) ? _pop!(h, index) : throw(KeyError(key))
end

"""
    pop!(collection, key[, default])

Delete and return the mapping for `key` if it exists in `collection`, otherwise return
`default`, or throw an error if `default` is not specified.

# Examples
```jldoctest
julia> d = OrderedRobinDict("a"=>1, "b"=>2, "c"=>3);

julia> pop!(d, "a")
1

julia> pop!(d, "d")
ERROR: KeyError: key "d" not found
Stacktrace:
[...]

julia> pop!(d, "e", 4)
4
```
"""
function pop!(h::OrderedRobinDict, key, default)
    index = get(h.dict, key, -1)
    (index > 0) ? _pop(h, index) : default
end

"""
    delete!(collection, key)

Delete the mapping for the given key in a collection, and return the collection.

# Examples
```jldoctest
julia> d = OrderedRobinDict("a"=>1, "b"=>2)
OrderedRobinDict{String,Int64} with 2 entries:
  "a" => 1
  "b" => 2

julia> delete!(d, "b")
OrderedRobinDict{String,Int64} with 1 entry:
  "a" => 1
```
"""
function delete!(h::OrderedRobinDict, key)
    pop!(h, key)
    return h
end

function _delete!(h::OrderedRobinDict, index)
    @inbounds h.dict[h.keys[index]] = -1
    h.count -= 1
    check_for_rehash(h) ? rehash!(h) : h
end

function get_first_filled_index(h::OrderedRobinDict)
    index = 1
    while (true)
        isslotfilled(h, index) && return index
        index += 1
    end
end

function get_next_filled_index(h::OrderedRobinDict, index)
    # get the next filled slot, including index and beyond
    while (index <= length(h.keys))
        isslotfilled(h, index) && return index
        index += 1
    end
    return -1
end

Base.@propagate_inbounds function iterate(h::OrderedRobinDict)
    isempty(h) && return nothing
    check_for_rehash(h) && rehash!(h)
    index = get_first_filled_index(h)
    return (Pair(h.keys[index], h.vals[index]), index+1)
end

Base.@propagate_inbounds function iterate(h::OrderedRobinDict, i)
    length(h.keys) < i && return nothing
    index = get_next_filled_index(h, i) 
    (index < 0) && return nothing
    return (Pair(h.keys[index], h.vals[index]), index+1)
end

filter!(f, d::Union{RobinDict, OrderedRobinDict}) = Base.filter_in_one_pass!(f, d)

function merge(d::OrderedRobinDict, others::AbstractDict...)
    K,V = _merge_kvtypes(d, others...)
    merge!(OrderedRobinDict{K,V}(), d, others...)
end

function merge(combine::Function, d::OrderedRobinDict, others::AbstractDict...)
    K,V = _merge_kvtypes(d, others...)
    merge!(combine, OrderedRobinDict{K,V}(), d, others...)
end

isordered(::Type{T}) where {T <: OrderedRobinDict} = true
