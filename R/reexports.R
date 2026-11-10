# Top-level re-exports from CohortUtilisation, CohortCosts, and CohortEconomics

# --- CohortUtilisation ---
#' @importFrom CohortUtilisation addInpatients addHospitalizations addInpatient addIcuStays
#' @export
CohortUtilisation::addInpatients
#' @export
CohortUtilisation::addHospitalizations
#' @export
CohortUtilisation::addInpatient
#' @export
CohortUtilisation::addIcuStays

#' @importFrom CohortUtilisation addEmergencyCare addEmergency addEmergencyVisits
#' @export
CohortUtilisation::addEmergencyCare
#' @export
CohortUtilisation::addEmergency
#' @export
CohortUtilisation::addEmergencyVisits

#' @importFrom CohortUtilisation addOutpatientVisits addVisits addPrescriptions addProcedures
#' @export
CohortUtilisation::addOutpatientVisits
#' @export
CohortUtilisation::addVisits
#' @export
CohortUtilisation::addPrescriptions
#' @export
CohortUtilisation::addProcedures

#' @importFrom CohortUtilisation computeHospitalizationCohorts compute_hospitalization_cohorts computeInfusionCohorts computeVisitCohorts compute_visit_cohorts
#' @export
CohortUtilisation::computeHospitalizationCohorts
#' @export
CohortUtilisation::compute_hospitalization_cohorts
#' @export
CohortUtilisation::computeInfusionCohorts
#' @export
CohortUtilisation::computeVisitCohorts
#' @export
CohortUtilisation::compute_visit_cohorts

#' @importFrom CohortUtilisation summariseUtilization tableUtilization plotUtilization
#' @export
CohortUtilisation::summariseUtilization
#' @export
CohortUtilisation::tableUtilization
#' @export
CohortUtilisation::plotUtilization


# --- CohortCosts ---
#' @importFrom CohortCosts addCosts summariseCosts tableCosts plotCosts
#' @export
CohortCosts::addCosts
#' @export
CohortCosts::summariseCosts
#' @export
CohortCosts::tableCosts
#' @export
CohortCosts::plotCosts


# --- CohortEconomics ---
#' @importFrom CohortEconomics init summarise_baseline extract_hcru extractHcru
#' @export
CohortEconomics::init
#' @export
CohortEconomics::summarise_baseline
#' @export
CohortEconomics::extract_hcru
#' @export
CohortEconomics::extractHcru

#' @importFrom CohortEconomics fit_ps adjust_ps assess_balance
#' @export
CohortEconomics::fit_ps
#' @export
CohortEconomics::adjust_ps
#' @export
CohortEconomics::assess_balance

#' @importFrom CohortEconomics compile_trajectories simulate_economics run_cea
#' @export
CohortEconomics::compile_trajectories
#' @export
CohortEconomics::simulate_economics
#' @export
CohortEconomics::run_cea

#' @importFrom CohortEconomics plot_ceac plot_plane table_summary
#' @export
CohortEconomics::plot_ceac
#' @export
CohortEconomics::plot_plane
#' @export
CohortEconomics::table_summary
