VERSION < v"0.1.0" && __precompile__()

module FITSUtils
export get_axis
export get_galprop_axis
export get_name_list
export get_spectra
export get_scatter

using FITSIO
using Printf

"""
    get_axis(header::FITSHeader, index::Int)

Get the grid array of a specified axis from an hdu header

# Arguments
* `header`: the header.
* `index`:  the index of specfied axis.
"""
function get_axis(header::FITSHeader, ind::Int)
  return map(i->header["CRVAL$ind"] + header["CDELT$ind"] * (i - 1), 1:header["NAXIS$ind"])
end

"""
    get_galprop_axis(header::FITSHeader)

Get the grid array of a axises from an GALPROP result hdu header

# Arguments
* `header`: the header.
"""
function get_galprop_axis(header::FITSHeader)
  result = Dict{String,Array{Real,1}}()
  pairs = header["NAXIS"] == 5 ? zip(["x", "y", "z", "E"], 1:4) : zip(["x", "E"], [1, 3])

  for pair in pairs
    result[pair[1]] = get_axis(header, pair[2])
  end
  result["E"] = map(e->10^e / 1e3, result["E"])
  return result
end

"""
    get_name_list(header::FITSHeader, index::Int)

Get the list of the exist particle (for GALPROP output)

# Arguments
* `header`: the header.
* `index`:  the index of the particle axis.
"""
function get_name_list(header::FITSHeader, index::Int)
  return map(i->get_name(header, i), 1:header["NAXIS$index"])
end
function get_name(header, ind::Int)
  index = @sprintf "%03d" ind
  return header["NAME$index"]
end

"""
    get_spectra(hdu::ImageHDU)

    Get the spectra of the exist particles (for GALPROP output)

# Arguments
* `hdu`: the hdu for GALPROP output.
"""
function get_spectra(hdu::ImageHDU)
  header = read_header(hdu)
  data = read(hdu)

  nlist = get_name_list(header, 4)

  rsun = 8.3
  xaxis = get_axis(header, 1)
  ilow = findlast(x->x<rsun, xaxis)
  iup = ilow + 1
  wlow = (xaxis[iup] - rsun) / (xaxis[iup] - xaxis[ilow])
  wup = (rsun - xaxis[ilow]) / (xaxis[iup] - xaxis[ilow])

  spectra = map((flow, fup)->flow * wlow + fup * wup, data[ilow,1,:,:], data[iup,1,:,:])
  result = Dict{String,Array{Float64,1}}()

  eaxis = map(x->10^x / 1e3, get_axis(header, 3)) # [GeV]
  for i in 1:length(nlist)
    result[nlist[i]] = map((e,f)->f / e^2 / 1e3, eaxis, spectra[:,i]) # MeV^2 cm^-2 sr^-1 s^-1 MeV^-1 -> cm^-2 sr^-1 s^-1 GeV^-1
  end
  result["eaxis"] = eaxis

  return result
end

function get_scatter(density::Array{T,4} where {T<:Real}, axis::Dict{String,Array{T,1}} where {T<:Real}, p::Real)
  iup = findfirst(v->v>p, axis["E"])
  iup = iup == nothing ? length(axis["E"]) : iup
  iup = iup == 1 ? 2 : iup

  ilow = iup - 1
  plow, p, pup = log(axis["E"][ilow]), log(p), log(axis["E"][iup])
  weights = [[ilow, (pup-p)/(pup-plow)], [iup, (p-plow)/(pup-plow)]]

  cube = mapreduce(v->density[:,:,:,floor(Int, v[1])]*v[2], +, weights, init=zeros(typeof(density[1,1,1,1]),size(density)[1:3]))

  scatters = Array{Array{Real,1},1}([[],[],[],[]])
  resize!(scatters, 4)

  for i in CartesianIndices(cube)
    (cube[i] == 0) && continue
    push!(scatters[1], axis["x"][i[1]])
    push!(scatters[2], axis["y"][i[2]])
    push!(scatters[3], axis["z"][i[3]])
    push!(scatters[4], cube[i])
  end

  return scatters
end

end  # FITSUtils
