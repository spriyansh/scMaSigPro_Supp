# Title: Analyze 60% Zero-Inflated Data with TradeSeq
# Author: Priyansh Srivastava
# Year: 2023

# Load libraries
suppressPackageStartupMessages(library(SingleCellExperiment))
suppressPackageStartupMessages(library(tradeSeq))
suppressPackageStartupMessages(library(gtools))
suppressPackageStartupMessages(library(scMaSigPro))
suppressPackageStartupMessages(library(microbenchmark))
suppressPackageStartupMessages(library(tidyverse))
suppressPackageStartupMessages(library(viridis))
suppressPackageStartupMessages(library(pryr))

# Set paths
base_string <- "../scMaSigPro_supp_data/"
base_string_2 <- ""
figPath <- paste0(base_string, "figures/")
figPath_hd <- paste0(figPath, "hd/")
figPath_lr <- paste0(figPath, "lr/")
tabPath <- paste0(base_string, "tables/")
helpScriptsDir <- paste0(base_string_2, "R_Scripts/helper_function/")

# Load Base data
paramEstimates <- readRDS(paste0(base_string, "benchmarks/00_Parameter_Estimation/output/setty_et_al_d1_splatEstimates.RDS"))

# Create Directory if does not exist
dir.create(figPath, showWarnings = FALSE, recursive = TRUE)
dir.create(figPath_hd, showWarnings = FALSE, recursive = TRUE)
dir.create(figPath_lr, showWarnings = FALSE, recursive = TRUE)
dir.create(tabPath, showWarnings = FALSE, recursive = TRUE)

# Load custom function
source(paste0(helpScriptsDir, "calcNormCounts.R"))
source(paste0(helpScriptsDir, "add_gene_anno().R"))
source(paste0(helpScriptsDir, "calc_bin_size.R"))

# Create Base parameters/ Same for All groups
params.groups <- newSplatParams(
  batch.rmEffect = TRUE, # No Batch affect
  batchCells = 3000, # Number of Cells
  nGenes = 2000, # Number of Genes
  seed = 2022, # Set seed
  mean.rate = paramEstimates@mean.rate,
  mean.shape = paramEstimates@mean.shape,
  lib.scale = paramEstimates@lib.scale,
  lib.loc = paramEstimates@lib.loc,
  bcv.common = paramEstimates@bcv.common,
  bcv.df = paramEstimates@bcv.df,
  dropout.type = "experiment",
  group.prob = c(0.6, 0.4),
  path.from = c(0, 0),
  de.prob = 0.3,
  de.facLoc = 1,
  path.nonlinearProb = 0.3,
  path.sigmaFac = 0.5,
  out.facLoc = paramEstimates@out.facLoc,
  dropout.mid = paramEstimates@dropout.mid,
  out.facScale = paramEstimates@out.facScale,
  out.prob = paramEstimates@out.prob,
  path.skew = c(0.4, 0.6),
  dropout.shape = -0.5,
  path.nSteps = c(1700, 1300)
)

# Simulate Object
sim.sce <- splatSimulate(
  params = params.groups,
  method = "paths",
  verbose = F
)

# Add gene Info
gene.info <- add_gene_anno(sim.sce = sim.sce)
gene.info <- gene.info[mixedsort(gene.info$gene_short_name), ]

# Readuce Dataset
keepGenes <- sample(rownames(rowData(sim.sce)), size = 1000, replace = F)
keepCells <- sample(rownames(colData(sim.sce)), size = 1500, replace = F)

# Extract raw counts
counts <- as.matrix(sim.sce@assays@data@listData$counts)
cell.metadata <- as.data.frame(colData(sim.sce))
gene.metadata <- as.data.frame(rowData(sim.sce))

# Subset the counts
counts.reduced <- counts[keepGenes, keepCells]
cell.metadata.reduced <- cell.metadata[keepCells, ]
gene.metadata.reduced <- gene.metadata[keepGenes, ]

sim.sce <- SingleCellExperiment(list(counts = counts.reduced))
colData(sim.sce) <- DataFrame(cell.metadata.reduced)
rowData(sim.sce) <- DataFrame(gene.metadata.reduced)

# Extract counts
counts <- as.matrix(sim.sce@assays@data@listData$counts)

# Perform Quantile Normalization as per-tradeSeq paper
normCounts <- FQnorm(counts)

# Extract Cell_metadata
cell_metadata <- as.data.frame(colData(sim.sce))

# Extract Gene_metadata
gene_metadata <- as.data.frame(rowData(sim.sce))

# Prepare Input
pseudotime_table <- cell_metadata[, c("Cell", "Step", "Group")]
lineage_table <- cell_metadata[, c("Cell", "Step", "Group")]

# Add Pseudotime Info
pseudotime_table$Pseudotime1 <- pseudotime_table$Step
pseudotime_table$Pseudotime2 <- pseudotime_table$Step
pseudotime_table <- pseudotime_table[, c("Pseudotime1", "Pseudotime2")]

# Hard Assignmnet for Lineage
lineage_table$Lineage1 <- ifelse(lineage_table$Group == "Path1", 1, 0)
lineage_table$Lineage2 <- ifelse(lineage_table$Group == "Path2", 1, 0)
lineage_table <- lineage_table[, c("Lineage1", "Lineage2")]

# Running scMaSigPro
scmp.obj <- as_scmp(sim.sce,
  from = "sce",
  align_pseudotime = T,
  additional_params = list(
    labels_exist = TRUE,
    exist_ptime_col = "Step",
    exist_path_col = "Group"
  ), verbose = F
)

# Squeeze
scmp.obj <- sc.squeeze(
  scmpObj = scmp.obj,
  bin_method = "Sturges",
  drop_fac = 0.5,
  verbose = F,
  aggregate = "sum",
  split_bins = F,
  prune_bins = F,
  drop_trails = F,
  fill_gaps = F
)

# Make Design
scmp.obj <- sc.set.poly(scmp.obj,
  poly_degree = 2
)

# Benchmark time
mbm <- microbenchmark(
  "TradeSeq_1_CPU" = {
    # Fit GAM
    sce.tradeseq <- fitGAM(
      counts = normCounts,
      pseudotime = pseudotime_table,
      cellWeights = lineage_table,
      parallel = F,
      nknots = 4, verbose = FALSE
    )
    gc()

    # One of the test
    patternRes <- patternTest(sce.tradeseq)
    gc()
  },
  "TradeSeq_8_CPU" = {
    # Fit GAM
    sce.tradeseq <- fitGAM(
      counts = normCounts,
      pseudotime = pseudotime_table,
      cellWeights = lineage_table,
      parallel = T,
      nknots = 4, verbose = FALSE
    )
    gc()

    # One of the test
    patternRes <- patternTest(sce.tradeseq)
    gc()
  },
  "ScMaSigPro_1_CPU" = {
    # Run p-vector
    scmp.obj <- sc.p.vector(
      scmpObj = scmp.obj, verbose = T,
      min_na = 1,
      parallel = F,
      offset = T,
      max_it = 1000
    )
    gc()

    # Run-Step-2
    scmp.obj <- sc.t.fit(
      scmpObj = scmp.obj, verbose = F,
      selection_method = "backward", parallel = F,
      offset = T
    )
    gc()
  },
  "ScMaSigPro_8_CPU" = {
    # Run p-vector
    scmp.obj <- sc.p.vector(
      scmpObj = scmp.obj, verbose = T,
      min_na = 1,
      parallel = T,
      n_cores = 8,
      offset = T,
      max_it = 1000
    )
    gc()

    # Run-Step-2
    scmp.obj <- sc.t.fit(
      scmpObj = scmp.obj, verbose = F,
      selection_method = "backward",
      parallel = T,
      n_cores = 8,
      offset = T
    )
    gc()
  },
  times = 1
)

# Process the results
data <- summary(mbm) %>% as.data.frame()
data$min_mean <- paste(round(data$mean / 60, digits = 3), "minutes")

compareBar_Time <- ggplot(data, aes(x = expr, y = mean, fill = expr)) +
  geom_bar(stat = "identity") +
  scale_y_continuous(
    breaks = seq(0, 120, 20),
    limits = c(0, 120)
  ) +
  labs(
    title = "Execution Times for a bifurcating trajectory",
    subtitle = "Number of Cells: 1500; Number of Genes: 1000",
    x = "Method",
    y = "Time (seconds)"
  ) +
  geom_text(aes(label = min_mean),
    position = position_dodge(width = 0.9),
    size = 3,
    vjust = 0.5, hjust = -0.1
  ) +
  coord_flip() +
  scale_fill_viridis(
    discrete = TRUE, name = "Custom Legend Title",
    breaks = c("TradeSeq_1_CPU", "ScMaSigPro_1_CPU", "TradeSeq_8_CPU", "ScMaSigPro_8_CPU"),
    labels = c("Custom Label 1", "Custom Label 2", "Custom Label 3", "Custom Label 4")
  ) +
  theme_minimal(base_size = 20) +
  theme(legend.position = "none", legend.justification = "left", legend.box.just = "left")

compareBar_Time

# Save the plot
write.table(
  x = data,
  file = paste0(tabPath, "Few_Cells_TS_Time_Profiling.txt"),
  quote = FALSE, sep = "\t", row.names = FALSE
)

# Save the plot
ggsave(
  plot = compareBar_Time,
  filename = paste0(figPath_hd, "04_tradeSeq_Time.png"),
  dpi = 600, width = 10
)
ggsave(
  plot = compareBar_Time,
  filename = paste0(figPath_lr, "04_tradeSeq_Time.png"),
  dpi = 150, width = 10
)
