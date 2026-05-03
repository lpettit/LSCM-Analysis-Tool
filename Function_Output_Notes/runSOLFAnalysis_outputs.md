# runSOLFAnalysis outputs

`runSOLFAnalysis` is the single-file workflow orchestrator. It runs the selected modules in order and returns the collected results.

## Outputs

| Field | What is measured | What it means physically |
| --- | --- | --- |
| `config` | Final configuration struct actually used for the run. | This is provenance metadata that records the analysis choices behind the results. |
| `bestParams` | Detection-parameter table returned by `autoTuneMounds` or `refineMounds`. | This is the mound-detection recipe used to generate Module 1 and downstream outputs. |
| `m1` | Full Module 1 results struct from `analyzeMounds`. | This contains mound locations and spacing metrics for the surface. |
| `cavResults` | Full Module 2 results struct from `analyzeCavities`, if Module 2 was selected. | This contains the cavity/depression measurements for the same surface. |
| `moundResults` | Full Module 3 results struct from `analyzeMoundShape`, if Module 3 was selected. | This contains the mound height, footprint, and morphology measurements for the same surface. |

## Physical interpretation

This function is not a measurement algorithm by itself. It packages the outputs of several measurement algorithms into one reproducible run record.
