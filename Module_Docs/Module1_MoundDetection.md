# Module 1: Mound Detection

See also: [analyzeMounds_outputs.md](../Function_Output_Notes/analyzeMounds_outputs.md)

## 1. Module Purpose And Scientific Questions Answered
Module 1 identifies the mound population on a surface and defines the centroid geometry that downstream modules rely on.

Scientifically, it answers questions such as:

- How many mounds are present in the field of view?
- Where are the mound centers located?
- How densely packed are the mounds?
- How regular or irregular is the local mound spacing?
- What neighborhood graph should downstream modules use as the baseline spatial scaffold?

Because Modules 2-4 all depend on Module 1 centroids or calibration, errors or biases here propagate into the rest of the tool.

## 2. Inputs, Dependencies, And Upstream Assumptions
Primary entry point:

- `analyzeMounds.m`

Inputs:

- raw surface file path
- tuning parameters from `autoTuneMounds`
- optional reflection-pit handling settings
- dilation and minimum-object-area settings
- calibration values for non-VK4 legacy image input

Dependencies:

- `readVK4.m` for preferred VK4 input
- Image Processing Toolbox
- bundled `vk4mat-main` dependency for VK4 reads

Upstream assumptions:

- VK4 input is preferred because it preserves calibrated height precision
- Module 1 is the authoritative source of:
  - centroids
  - image calibration
  - display image used by later diagnostics
- border-excluded mound detection is intentional so downstream modules do not build statistics on incomplete edge features

## 3. Recommended Reading Path
For a first pass, read in this order:

1. detection pipeline
2. centroid filtering and border treatment
3. spacing and density calculation
4. Delaunay and alpha-shape trimming logic
5. figure guide

If you only need quick field lookup, use the linked output-note page instead.

## 4. Calculation Workflow
### 4.1 Load calibrated surface data
The module accepts either:

- VK4 input, which is the preferred path
- legacy image input, which requires manually supplied calibration

For VK4 input, the module reads:

- calibrated height map `Z`
- lateral calibration `xy_um_per_px`
- total height range `total_height_um`

It also derives a `uint8` display image `I_raw` from the calibrated height map so downstream modules can use the same visual/intensity-style representation without re-reading the raw file.

### 4.2 Run the mound-detection pipeline
The detection pipeline uses the tuned preprocessing and morphology settings from `autoTuneMounds` and related helpers. Its purpose is to locate candidate mound regions and convert them into centroid positions.

This stage is operationally simple but scientifically important: it defines what the project means by a mound "instance" for all downstream analysis.

### 4.3 Build centroid geometry
Once centroids are detected, the module constructs a Delaunay triangulation over the centroid coordinates.

This triangulation is used as the initial neighborhood graph because it connects nearby mounds without requiring a user-chosen spacing threshold.

### 4.4 Trim the outer-edge geometry with an alpha-shape workflow
A plain Delaunay graph tends to include long, edge-driven connections near the border of the image. Those connections can distort spacing summaries.

To reduce that problem, the module:

- estimates an initial alpha scale from Delaunay edge lengths
- iterates to a self-consistent alpha-shape solution
- keeps edges supported by the resulting alpha-triangulation

This is a boundary-aware way to keep local mound-to-mound geometry while suppressing unrealistic outer boundary bridges.

### 4.5 Compute spacing statistics
From the trimmed edge set, the module computes:

- spacing distances in pixels
- spacing distances in micrometers
- mean spacing
- spacing spread
- coefficient of variation

The coefficient of variation is especially useful because it normalizes spread by the mean and therefore acts as a compact regularity/disorder indicator.

### 4.6 Compute effective area and mound density
Mound density is not computed from the full raw image rectangle. Instead, the module uses an effective centroid-bounding region based on the nearest retained centroids to each edge.

This choice matters physically because the detection workflow already excludes edge features. Using the full image area anyway would understate the density of the analyzed mound population.

## 5. Analysis Groups Within The Workflow
### Detection pipeline
This group defines which features count as mounds and where their centroids lie.

### Centroid filtering and border handling
This group determines which candidate mounds are trusted enough to support downstream science.

### Spacing and network analysis
This group turns centroid geometry into spacing distributions, neighborhood connections, and density summaries.

### Provenance and calibration carry-through
This group ensures downstream modules inherit:

- calibrated height map
- display image
- file identity
- spatial scale

## 6. Output Interpretation
The most important Module 1 outputs are:

- `centroids`
  - the anchor coordinates for the whole pipeline
- `n_mounds`
  - the working mound count for the field of view
- `density_mm2`
  - how densely the mound population packs the analyzed surface
- `nn_mean_um`
  - characteristic mound spacing
- `nn_std_um` and `nn_cv`
  - how uniform or irregular that spacing is
- `trimmed_edges`
  - the neighborhood graph trusted for downstream spatial interpretation

Interpret these outputs together rather than in isolation. For example:

- high density with low `nn_cv` suggests a tightly packed and relatively regular mound field
- similar density but larger `nn_cv` suggests comparable packing with poorer local regularity

## 7. Assumptions, Choices, And Why They Were Made
- VK4 is preferred over BMP-like input because quantization loss in 8-bit height maps can affect downstream interpretation.
- Border exclusion is intentional because partial edge features distort centroid-based statistics.
- Alpha-shape trimming is preferred over raw Delaunay usage because boundary-spanning long edges are usually artifacts of limited field of view, not true local neighbors.
- The effective area for density is based on the centroid field rather than the full image rectangle so the denominator matches the analyzed mound population.

## 8. Diagnostics And Figure Guide
### `*_delaunay.png`
- Workflow stage: centroid geometry and retained network
- Type: process and on-surface visualization
- Shows: detected centroids and the retained trimmed Delaunay web
- Use it for:
  - checking whether mound centers were found in the right places
  - seeing whether long edge-bridging connections were suppressed
- Watch for:
  - obviously missing mound regions
  - extra centroids on non-mound features
  - long retained edges near boundaries that suggest trimming is insufficient

### `*_spacing.png`
- Workflow stage: spacing distribution summary
- Type: distribution/statistical figure
- Shows: nearest-neighbor spacing distribution in physical units
- Use it for:
  - identifying the characteristic spacing scale
  - judging whether the distribution is tight, broad, skewed, or multi-modal
- Watch for:
  - very broad tails that may indicate mixed mound populations or poor detection
  - multiple peaks that may indicate multiple spacing families on the same surface

### `*_results.xlsx`
- Workflow stage: export and downstream review
- Type: summary/supporting output
- Shows: per-edge, per-centroid, and summary tables rather than a rendered image
- Use it for:
  - verifying numerical spacing outputs behind the figures
  - supporting later cross-module analysis

## 9. Known Limitations And Caution Points
- Any centroid bias propagates into Modules 2-4.
- Module 1 detects mound centers, not full mound footprints or physical bases.
- Spacing summaries are field-of-view dependent and can shift if the image captures a strongly nonuniform region of the surface.
- Density and regularity are only as trustworthy as the mound-detection result.

## 10. Change Log For Finalized Methodology
- 2026-05-08: Created the long-form finalized Module 1 scientific-methods document and aligned it with the current output-note layer.
