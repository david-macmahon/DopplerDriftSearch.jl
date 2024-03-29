module DopplerDriftSearch

export create_fdr

# intfdr.jl
export intshift, intshift!
export intfdr, intfdr!

# fftfdr.jl
export fftfdr_workspace, fftfdr_workspace!
export fdshiftsum, fdshiftsum!
export fdshift, fdshift!
export fftfdr, fftfdr!

"""
Create an uninitialized `Matrix` suitable for use with `intfdr!` or `fftfdr!`
and the given `spectrogram` and `Nr` (number of rates).  The returned `Matrix`
will be similar to `spectrogram` in type and size of first dimension, but its
second dimension will be `Nr`.
"""
function create_fdr(spectrogram, Nr::Integer)
    Nf = size(spectrogram, 1)
    similar(spectrogram, Nf, Nr)
end

"""
Create an uninitialized `Matrix` suitable for use with `intfdr!` or `fftfdr!`
and the given `spectrogram` and `rates`.  The returned `Matrix` will be similar
to `spectrogram` in type and size of first dimension, but its second dimension
will be sized by the length of `rates`.
"""
function create_fdr(spectrogram, rates)
    create_fdr(spectrogram, length(rates))
end

include("intfdr.jl")
include("fftfdr.jl")

end # module DopplerDriftSearch
