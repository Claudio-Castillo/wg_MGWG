Jon Deroba 20 June 2019

SAM fit with default settings other than: estimation of Beverton Holt, I fixed the N age 2-20 process variance to zero because it was estimating zero and was causing convergence issues.  I also had to add some extra noise to the catch data, which resolved two issues: 1) observation variance near zero, 2) estimates of SSB, F, and R were too high in scale.  Adding this noise fixed the issues.  Steepness and reference points estimated using the terminal year life history values.  Diagnostics look OK.  The estiamte variance in recruitment is very near the true value of 0.3, but the time series visually looks way noisier than the truth.

alpha = 393; beta=104
