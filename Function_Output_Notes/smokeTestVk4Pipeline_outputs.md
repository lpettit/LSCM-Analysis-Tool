# smokeTestVk4Pipeline outputs

`smokeTestVk4Pipeline` is the lightweight regression check for one representative `.vk4` file.

## Runtime result

This function does not return a value. It prints pass/fail information to the command window and throws an error if the pipeline fails.

## What it checks

- `readVK4` can load the test file
- `autoTuneMounds` can tune detection on that file
- `analyzeMounds`, `analyzeCavities`, and `analyzeMoundShape` complete without runtime errors
- selected Module 3 fields exist and contain finite preferred values

## Physical interpretation

This is not a measurement function. It is a sanity check that the analysis stack still works on a known representative SOLF surface.
