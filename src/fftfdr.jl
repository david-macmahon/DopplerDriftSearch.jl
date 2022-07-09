using AbstractFFTs
# We need to depend on FFTW for access to its flags constants because
# AbstractFFTs defines the planning flags to be "a bitwise-or of FFTW planner
# flags".  For more details, see:
# https://github.com/JuliaMath/AbstractFFTs.jl/issues/71
import FFTW
using LinearAlgebra

function phasor(k::Integer, n::Integer, r::Float32, N::Integer)
    cispi(-2*k*n*r/N)
end

function phasor(i::CartesianIndex, r, N)
    phasor(i[1]-1, i[2]-1, r, N)
end

"""
Create all the required intermediate storage buffers and FFT plan objects needed
for creating a frequency drift rate matrix for `spectrogram` using `fftfdr` and
return them in a container suitable for use as the `workspace` argument to
`fftfdr`.  By default, the spectra in `spectrogram` have no alignment
constraints, but if the columns of `fftfdr`'s output buffer will be suitably
aligned for the FFT implementation, then `bunalingned` may be passed as false.
This will usually be the case if the number of frequency channels has several
factors of 2, but it depends on the specifics of the FFT implementation.

The workspace also includes an FFT plan suitable for generating a *de-dopplered*
spectrogram for a given rate.  This functionality is provided by `fdshift!`.
"""
function fftfdr_workspace(spectrogram::AbstractMatrix{<:Real}; bunaligned=true)
    Nf, Nt = size(spectrogram)
    mat = similar(spectrogram, Complex{eltype(spectrogram)}, Nf÷2+1, Nt)
    vec = similar(mat, Nf÷2+1)
    fplan = plan_rfft(spectrogram, 1)
    bplan1d = plan_brfft(vec, Nf; flags=FFTW.ESTIMATE|(bunaligned ? FFTW.UNALIGNED : 0))
    # The `2d` in `bplan2d` refers to the input/output arrays.
    # The dimensionality of the FFT is still 1D along the first dimension.
    bplan2d = plan_brfft(mat, Nf, 1) # Assume output will always be aligned for now
    (mat=mat, vec=vec, fplan=fplan, bplan1d=bplan1d, bplan2d=bplan2d)
end

function fdshift!(dest::AbstractMatrix, spectrogram::AbstractMatrix, rate, workspace=nothing)
    @assert size(dest) == size(spectrogram) "destination is the wrong size"

    if workspace === nothing
        workspace = fftfdr_workspace(spectrogram)
    end

    Nf = size(spectrogram, 1)

    # Calculate forward FFT of spectrogram to get into the Fourier domain
    mul!(workspace.mat, workspace.fplan, spectrogram)

    # Multiply the fourier domain spectra by the doppler rate phasors.
    workspace.mat .*= phasor.(CartesianIndices(workspace.mat), Float32(rate), Nf)

    # Store the backwards FFT of `workspace.mat` into `dest`.
    mul!(dest, workspace.bplan2d, workspace.mat)
end

function fdshift(spectrogram::AbstractMatrix, rate, workspace=nothing)
    dest = similar(spectrogram)
    fdshift!(dest, spectrogram, rate, workspace)
end

function fdshiftsum!(dest::AbstractVector, spectrogram::AbstractMatrix, rate, workspace=nothing)
    Nf = size(spectrogram, 1)
    @assert length(dest) == Nf "Incorrect destination size"

    if workspace === nothing
        workspace = fftfdr_workspace(spectrogram)
    end

    # Calculate forward FFT of spectrogram to get into the Fourier domain
    mul!(workspace.mat, workspace.fplan, spectrogram)

    # Multiply the fourier domain spectra by the doppler rate phasors.
    workspace.mat .*= phasor.(CartesianIndices(workspace.mat), Float32(rate), Nf)

    # Sum over time in the Fourier domain
    sum!(workspace.vec, workspace.mat)

    # Store the backwards FFT of `workspace.vec` into `dest`.
    mul!(dest, workspace.bplan1d, workspace.vec)
end

"""
Same as the `fftfdr` function, but store the results in `fdr`, which is also
returned.  The size of `fdr` must be `(size(spectrogram,1), length(rates))`.
"""
function fftfdr!(fdr, spectrogram, rates, workspace=nothing)
    Nf = size(spectrogram, 1)
    Nr = length(rates)
    @assert size(fdr) == (Nf, Nr)
    for (i,r) in enumerate(rates)
        fdshiftsum!(@view(fdr[:,i]), spectrogram, r, workspace)
    end
    return fdr
end

"""
Compute the frequency drift rate matrix for the given `spectrogram` and `rates`
values using FFT shifting of each frequency spectrum.  The first (fastest
changing) dimension of `spectrogram` is frequency and the second dimension
(slowest changing) is time.  The size of the returned frequency drift rate
matrix will be `(size(spectrogram,1), length(rates))`.  A workspace object
obtained from `fftfdr_workspace` may be passed as `workspace`.  If `workspace`
is omitted or `nothing`, then a workspace object will be created by calling
`fftfdr_workspace`.
"""
function fftfdr(spectrogram, rates, workspace=nothing)
    Nf = size(spectrogram, 1)
    Nr = length(rates)
    fdr = similar(spectrogram, Nf, Nr)
    fftfdr!(fdr, spectrogram, rates, workspace)
end
