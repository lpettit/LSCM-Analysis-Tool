# Module 4: Spatial Order

See also: [analyzeSpatialOrder_outputs.md](../Function_Output_Notes/analyzeSpatialOrder_outputs.md)

## 1. Module Purpose And Scientific Questions Answered
Module 4 describes how ordered or disordered the mound pattern is as a 2D population.

Scientifically, it addresses questions such as:

- How hexatically ordered is the mound field?
- How regular are the local neighbor shells?
- Does the mound population show a clear preferred spacing scale?
- How uniform are the local cells and local densities?
- Which regions of the image are more ordered, disordered, or boundary-affected?

This module complements Module 1 spacing by adding richer order diagnostics rather than only mean nearest-neighbor distance.

## 2. Inputs, Dependencies, And Upstream Assumptions
Primary entry point:

- `analyzeSpatialOrder.m`

Inputs:

- `m1` results from Module 1
- optional output directory

Dependencies:

- Module 1 centroids, trimmed edges, calibration, and display image
- Image Processing Toolbox

Upstream assumptions:

- Module 1 centroid geometry is trustworthy enough to represent the mound population
- the trimmed Delaunay graph is the current neighbor-definition baseline
- the mound field is being interpreted as a planar point pattern rather than a 3D lattice

## 3. Recommended Reading Path
A useful reading order is:

1. neighbor definition
2. `psi6` orientational-order workflow
3. boundary-aware interpretation tiers
4. pair-distribution workflow
5. Voronoi/local-density workflow
6. neighbor-shell workflow
7. figure guide

## 4. Calculation Workflow
### 4.1 Start from the Module 1 centroid field
Module 4 uses the centroid set and trimmed Delaunay edges created by Module 1.

That means Module 4 does not redetect mounds. It interprets the spatial order of the existing Module 1 mound population.

### 4.2 Define the neighbor graph
The current neighbor definition is the trimmed Delaunay graph.

This choice avoids introducing an extra arbitrary spacing cutoff while still giving each mound a local bond network for order calculations.

### 4.3 Compute local and global planar sixfold order
The core orientational-order metric is planar `psi6`.

For each mound, Module 4 computes a complex local sixfold order value from the bond angles to its neighbors, then derives:

- local magnitude
- local phase
- field-level global magnitude
- interior-only summaries

This is the main answer to the question, "How hexatically ordered is the mound arrangement?"

### 4.4 Mark boundary-affected mounds and assign interpretation tiers
The module identifies a boundary margin based on mound spacing and labels mounds near the outer region as boundary-affected.

For the remaining mounds, it assigns heuristic interpretation tiers such as:

- low
- moderate
- high

These are not fundamental physical laws. They are reporting aids built on top of the physical `psi6` metric.

### 4.5 Compute pair-distribution behavior
The module computes an approximate 2D pair distribution `g(r)` from centroid-to-centroid distances.

This captures radial order:

- whether a characteristic spacing scale stands out clearly
- how strong the first-shell spacing peak is
- whether spacing order persists into larger separations

### 4.6 Compute full neighbor-shell spacing metrics
In addition to the Delaunay bond set, the module sorts full pair distances for each mound and extracts:

- first-neighbor distance
- second-neighbor distance
- third-neighbor distance

This gives a fuller spacing-shell picture than nearest-neighbor distance alone.

### 4.7 Compute Voronoi cell and local-density metrics
The module computes clipped Voronoi cells using a border-aware construction and then derives:

- finite cell area
- inverse-area local density
- clipping and validity flags

This is a complementary local-packing view that does not rely only on bond lengths.

### 4.8 Build comparison-ready labels
Finally, the module condenses the richer outputs into quick comparison helpers such as:

- radial order label
- orientational order label
- one-line comparison summary

These are intentionally higher-level reporting outputs built on the more fundamental spatial metrics above.

## 5. Analysis Groups Within The Workflow
### Neighbor-graph definition
This group defines which mound-to-mound relations count as local bonds.

### Orientational-order group
This group measures local and field-level sixfold order.

### Radial-order group
This group uses pair-distribution and neighbor-shell metrics to describe spacing regularity.

### Voronoi and local-density group
This group describes local packing cell size and density variation.

### Interpretation-tier group
This group converts physical metrics into compact comparison categories for practical reporting.

## 6. Output Interpretation
Start with:

- `global_psi6_interior`
  - field-level interior orientational order
- `mean_local_psi6_interior`
  - average local orientational order
- `first_peak_r_um` and `first_peak_g_r`
  - characteristic radial-order scale and strength
- `nn1_cv`, `nn2_cv`, `nn3_cv`
  - neighbor-shell regularity
- `voronoi_area_mean_um2` and `local_density_mean_um2_inv`
  - average local packing cell size and density
- `comparison_summary_line`
  - quick summary for comparing surfaces

Interpretation examples:

- strong `psi6` with a clear `g(r)` first peak suggests a more ordered mound population
- weaker `psi6` with broad neighbor-shell CVs suggests local spatial disorder
- broad Voronoi area spread suggests nonuniform local packing even if mean spacing looks similar

## 7. Assumptions, Choices, And Why They Were Made
- Planar `psi6` is used instead of a 3D-style order metric because the mound pattern is being interpreted as a 2D surface point field.
- The trimmed Delaunay graph is used as the neighbor scaffold because it is local, natural for point patterns, and already available from Module 1.
- Boundary mounds are treated separately because order metrics near a cropped field edge are easier to misread.
- Interpretation tiers and comparison labels are intentionally heuristic and should be read as reporting aids, not as fundamental physical categories.

## 8. Diagnostics And Figure Guide
### `*_spatial_order_psi6.png`
- Workflow stage: orientational-order mapping
- Type: on-surface/spatial map
- Shows: local `psi6` magnitude over the mound field
- Use it for:
  - seeing where order is strong or weak
  - checking whether high-order regions cluster spatially
- Watch for:
  - apparent low-order rings driven mainly by boundary effects

### `*_spatial_order_defects.png`
- Workflow stage: coordination and interpretation tiers
- Type: diagnostic/spatial map
- Shows: coordination-number map and low/moderate/high order-tier classification
- Use it for:
  - checking whether local defects align with visually irregular zones
- Watch for:
  - over-interpretation of heuristic tier labels without checking the underlying `psi6`

### `*_voronoi_density.png`
- Workflow stage: Voronoi/local-density interpretation
- Type: spatial map plus distribution figure
- Shows: clipped Voronoi cells, local density view, and Voronoi area histogram
- Use it for:
  - seeing how local packing varies across the field
- Watch for:
  - edge-driven clipping effects
  - invalid cells concentrated in problematic regions

### `*_voronoi_cells.png`
- Workflow stage: Voronoi geometry review
- Type: on-surface visualization
- Shows: Voronoi polygons colored by cell area
- Use it for:
  - visually validating local cell-size interpretation
- Watch for:
  - unexpected geometric artifacts near borders

### `*_voronoi_area_hist.png`
- Workflow stage: Voronoi distribution summary
- Type: distribution/statistical figure
- Shows: finite Voronoi area distribution
- Use it for:
  - comparing local packing breadth across surfaces
- Watch for:
  - very broad or multi-modal area distributions that indicate heterogeneous ordering

### `*_neighbor_shells.png`
- Workflow stage: neighbor-shell analysis
- Type: mixed spatial/distribution figure
- Shows: first-, second-, and third-neighbor maps plus shell-distance histograms
- Use it for:
  - comparing short-range and slightly longer-range spacing regularity
- Watch for:
  - shell overlap or broadening that suggests poor radial order

### `*_pair_distribution.png`
- Workflow stage: radial-order analysis
- Type: summary/comparison figure
- Shows: approximate `g(r)` with first-peak annotation
- Use it for:
  - identifying the characteristic spacing shell and the strength of radial order
- Watch for:
  - noisy or weak first peaks that make radial-order labels less stable

### `*_bond_angles.png`
- Workflow stage: bond-orientation analysis
- Type: distribution/orientation figure
- Shows: bond-angle histogram and polar orientation view
- Use it for:
  - checking preferred bond directions or anisotropy
- Watch for:
  - broad flattened angle distributions on surfaces expected to show directional alignment

### `*_spatial_order.xlsx`
- Workflow stage: export and detailed review
- Type: summary/supporting output
- Shows: per-mound, Voronoi, pair, bond, neighbor-shell, comparison, and summary sheets
- Use it for:
  - exact downstream review and cross-surface comparisons

## 9. Known Limitations And Caution Points
- Module 4 inherits any centroid bias from Module 1.
- The interpretation tiers are heuristic and should not replace the underlying physical metrics.
- Voronoi behavior near the image boundary remains harder to interpret than interior cells.
- A surface can have similar mean spacing to another surface while still differing strongly in local order, so single summary numbers should not be overused.

## 10. Change Log For Finalized Methodology
- 2026-05-08: Created the long-form finalized Module 4 scientific-methods document and aligned it with the current Module 4 output-note layer and figure set.
