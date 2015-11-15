module NNCuda

using CUDArt

const ptxdict = Dict()
const mdlist = Array(CuModule, 0)

function mdinit(devlist)
    global ptxdict
    global mdlist
    isempty(mdlist) || error("mdlist is not empty")
    for dev in devlist
        device(dev)
        md = CuModule(joinpath(Pkg.dir(), "NearestNeighbors/deps/cu_kernels.ptx"), false)  # false means it will not be automatically finalized
        ptxdict[(dev, "colsumsq!", Float32)] = CuFunction(md, "colsumsq_float")
        ptxdict[(dev, "colsumsq!", Float64)] = CuFunction(md, "colsumsq_double")
        ptxdict[(dev, "add_vecs!", Float32)] = CuFunction(md, "add_vecs_float")
        ptxdict[(dev, "add_vecs!", Float64)] = CuFunction(md, "add_vecs_double")
        push!(mdlist, md)
    end
end

mdclose() = (for md in mdlist; unload(md); end; empty!(mdlist); empty!(ptxdict))

function init(f::Function, devlist)
    local ret
    mdinit(devlist)
    try
        ret = f(devlist)
    finally
        mdclose()
    end
    ret
end

function colsumsq!{T}(summ::CudaVector{T}, data::CudaPitchedArray{T, 2})
    dev = device(data)
    function1 = ptxdict[(dev, "colsumsq!", T)]
    nsm = attribute(device(), CUDArt.rt.cudaDevAttrMultiProcessorCount)
    mul = min(32, ceil(Int, length(data)/(256*nsm)))
    launch(function1, mul*nsm, 256, (data, size(data, 1), size(data, 2), pitchel(data), summ))
end

function add_vecs!{T}(data::CudaPitchedArray{T, 2}, sa::CudaVector{T}, sb::CudaVector{T})
    dev = device(data)
    m = size(data, 1)
    n = size(data, 2)
    nblocky = ceil(Int, m / 16)
    nblockx = ceil(Int, n / 16)
    function1 = ptxdict[(dev, "add_vecs!", T)]
    nsm = attribute(device(), CUDArt.rt.cudaDevAttrMultiProcessorCount)
    mul = min(32, ceil(Int, length(data)/(256*nsm)))
    launch(function1, (nblocky, nblockx), (16, 16), (data, m, n, pitchel(data), sb, sa))
end

end

