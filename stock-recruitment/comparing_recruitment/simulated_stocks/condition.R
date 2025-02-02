# condition.R - DESC
# /condition.R

# Copyright European Union, 2018
# Author: Iago Mosqueira (EC JRC) <iago.mosqueira@ec.europa.eu>
#
# Distributed under the terms of the European Union Public Licence (EUPL) V.1.1.


# -- SETUP

# INSTALL PKGS from FLR and CRAN dependencies

# install.packages(c("FLife", "FLasher", "ggplotFL", "data.table",
#   "doParallel", "rngtools", "doRNG"),
#   repos=structure(c(CRAN="https://cran.uni-muenster.de/",
#   FLR="http://flr-project.org/R")))

# LOAD PKGS

library(FLife)
library(FLasher)
library(ggplotFL)
library(data.table)

# GET colinmillar:::mlnoise()

source("R/functions.R")

# VARIABLES

lastyr <- 100
its <- 300
ess_catch=200
ess_index=100

set.seed(1809)


# -- INITIAL population

# SET initial parameters:

# h = 0.65, B0 = 1000, Linf = 90
par <- FLPar(linf=90, a=0.00001, sl=1, sr=2000, a1=4, s=0.65, v=1000)

# PLOT selex

# ages 1-20+, fbar = 4-7
range <- c(min=1, max=20, minfbar=4, maxfbar=7, plusgroup=20)

# GET full LH params set
parg <- lhPar(par)

# M Jensen

mJensen <- function(length, params){
  length[]=params["a50"]
  1.45 / length
}

# GET equilibrium FLBRP

eql <- lhEql(parg, range=range, m=mJensen)

# COERCE

stk <- as(eql, "FLStock")

# BUG: FLife does not set right units
units(stk) <- list(
  landings="t", landings.n="1000", landings.wt="kg",
  discards="t", discards.n="1000", discards.wt="kg",
  catch="t", catch.n="1000", catch.wt="kg",
  stock="t", stock.n="1000", stock.wt="kg",
  m="m")

srr <- as(eql, "predictModel")

# EXTEND w/F=0.0057226 until year=lastyr

om <- fwdWindow(stk[,2], eql, end=lastyr)

om <- propagate(om, its)


# -- DEVIANCES

# rand walk

rwfoo <- function(n, sd) {
  x <- cumsum(rnorm(n, sd = sd))
  exp(x - mean(x))
}

rwdev <- Reduce(combine, FLQuants(lapply(1:its, function(x)
  FLQuant(rwfoo(n=98, sd=0.05), dimnames=list(year=3:lastyr)))))

# lnormal

lndev03 <- rlnorm(its, FLQuant(0, dimnames=list(year=3:lastyr)), 0.3)
lndev06 <- rlnorm(its, FLQuant(0, dimnames=list(year=3:lastyr)), 0.6)

devs <- FLQuants(rw=rwdev, ln03=lndev03, ln06=lndev06)

# -- SRRs

# bevholt
bhm <- srr

# ricker abPars()
rim <- predictModel(model=ricker,
  params=FLPar(a=1.77027, b=0.00155))

# geomean asymptote BH
gmm <- predictModel(model=geomean, params=FLPar(a=400)) 

# hockeystick 70% asymptote BH
hsm <- predictModel(model=rec ~ FLQuant(ifelse(c(ssb) <= c(b), c(a) * c(ssb), c(a) * c(b)),
  dimnames = dimnames(ssb)), params=FLPar(a=0.9, b=450))

srms <- list(bhm=bhm, rim=rim, gmm=gmm, hsm=hsm)

# -- TRAJECTORIES

# Refpt

FMSY <- c(fmsy(eql))

# Roller coaster

rcc <- fwdControl(year=3:lastyr, quant="f", value=c(
  rep(0.001, length=40),
  seq(0.001, FMSY * 2.0, length=20),
  rep(FMSY * 2.0, 18),
  seq(FMSY * 2.0, FMSY * 0.75, length=20)
  ))

# Low F: 0.30 * FMSY

lfc <- fwdControl(
  # year 3-40, F=0.001
  list(year=seq(3, 40), quant="f", value=0.001),
  # year 41-lastyr, F=FMSY * [0.2-0.4]
  list(year=seq(41, lastyr), quant="f", value=FMSY * runif(60, 0.2, 0.4)))

# High F: 1.30 * FMSY

hfc <- fwdControl(
  # year 3-40, F=0.001
  list(year=seq(3, 40), quant="f", value=0.001),
  # year 41-lastyr, F=FMSY * [1.2-1.4]
  list(year=seq(41, lastyr), quant="f", value=FMSY * runif(60, 1.2, 1.4)))

trajs <- list(rcc=rcc, lfc=lfc, hfc=hfc)

# -- SCENARIOS

sce <- list(
  devs=c('rwdev', 'lndev03', 'lndev06'),
  srm=c('bhm', 'rim', 'gmm', 'hsm'),
  traj=c('rcc', 'lfc', 'hfc'))

runs <- expand.grid(sce)

# -- PROJECT OMs

# WARNING: This code runs (better) in Linux, using multicore

library(parallel)
library(doParallel)

# REGISTER ncores
ncores <- min(nrow(runs), floor(detectCores() * 0.8))

registerDoParallel(ncores)

# SET parallel RNG seed
library(doRNG)
registerDoRNG(8234)

# LOOP over scenarios
out <- foreach(i=seq(nrow(runs)),
  .final=function(i) setNames(i, seq(nrow(runs)))) %dopar% {

  # GET elements
  devs <- get(ac(runs[i,"devs"]))
  srm <- get(ac(runs[i,"srm"]))
  traj <- get(ac(runs[i,"traj"]))

  # FWD
  fwd(om, sr=srm, control=traj, deviances=devs)
}

oms <- FLStocks(out)




# OUTPUT real ssb, rec, naa, fbar, faa, catch.sel, params, model

metrics <- lapply(oms, metrics, list(ssb=ssb, rec=rec, naa=stock.n,
  fbar=fbar, faa=harvest, catch.sel=catch.sel))

srrs <- rbindlist(lapply(
  list(bhm=bhm, rim=rim, gmm=gmm, hsm=hsm)[runs$srm], function(x) {
    cbind(data.frame(model=SRModelName(model(x)),
    data.frame(as(params(x), 'list'))))
  }), fill=TRUE)

# RUNS: devs, srm, traj, model, a, b
runs <- cbind(runs, srrs)

 
# -- OBSERVATIONS

# CATCH.N, mnlnoise w/ 10% CV, 200 ESS

catch.n <- FLQuants(mclapply(oms, function(x) {
  mnlnoise(n=its, numbers=catch.n(x),
  sdlog=sqrt(log(1 + ((catch(x) * 0.10)^2 / catch(x)^2))), ess=ess_catch)
  }, mc.cores=ncores))

# SURVEY, mnlnoise w/ 20% CV, 100 ESS

# Q
survey.q <- 3e-3

# SEL
a50 <- 2.3
slope <- 0.4
survey.sel <- FLQuant(1 / ( 1 + exp(-(seq(1, 20) - a50) / slope)),
  dimnames=dimnames(m(oms[[1]])))

timing <- 0

index <- FLQuants(mclapply(oms, function(x) {

  mnlnoise(n=its, numbers=stock.n(x) * exp(-(harvest(x) * timing + m(x) *
    timing)) %*% survey.sel * survey.q,
    sdlog=sqrt(log(1 + ((stock(x) * 0.20)^2 / stock(x)^2))), ess=ess_index)
    }, mc.cores=ncores))


# -- RESULTS

mets <- function(x)
  FLQuants(list(rec=rec(x)[,-1], ssb=ssb(x)[,-50], fbar=fbar(x)[,-50]))

# RES

res <- rbindlist(mclapply(oms, function(x)
  # REC and SSB lag = 1
  data.table(model.frame(metrics(x, mets), drop=TRUE)), mc.cores=ncores),
    idcol="run")
# TODO run year iter    rec    ssb     fbar fmult alpha beta steepness virginSSbiomass model internal
res[, c("model", "internal") := .("om", NA)]

# SAVE

save(res, runs, file="out/metrics.RData", compress="xz")

save(oms, eql, index, catch.n, runs, devs, srms, trajs,
  file="out/oms.RData", compress="xz")

# EXPORT test case: rcc bhm lndev03

test <- model.frame(metrics(iter(oms[[1]], 1), mets), drop=TRUE)

write.csv(test, file="test/test_rcc-bhm-lndev03.csv")


