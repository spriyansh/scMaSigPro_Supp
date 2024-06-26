# Title: Simulate dataset to test with tradeSeq
# Author: Priyansh Srivastava
# Email: spriyansh29@gmail.com
# Year: 2023

# Load libraries
suppressPackageStartupMessages(library(splatter))
suppressPackageStartupMessages(library(SingleCellExperiment))
suppressPackageStartupMessages(library(coop))
suppressPackageStartupMessages(library(gtools))
suppressPackageStartupMessages(library(tidyverse))
suppressPackageStartupMessages(library(ggpubr))
suppressPackageStartupMessages(library(parallel))
suppressPackageStartupMessages(library(scuttle))
suppressPackageStartupMessages(library(scater))
suppressPackageStartupMessages(library(Seurat))
suppressPackageStartupMessages(library(viridis))

# Set paths
base_string <- "../scMaSigPro_supp_data/"
base_string_2 <- ""
rdsPath <- paste0(base_string, "comparison/sim/")
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
dir.create(rdsPath, showWarnings = FALSE, recursive = TRUE)

# Load Custom Functions
source(paste0(helpScriptsDir, "plot_simulations().R"))
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

# Proportion of true Sparsity
trueSparsity <- round(sparsity(as.matrix(sim.sce@assays@data@listData$TrueCounts)) * 100)
simulatedSparsity <- round(sparsity(as.matrix(sim.sce@assays@data@listData$counts)) * 100) - trueSparsity
totSparsity <- round(sparsity(as.matrix(sim.sce@assays@data@listData$counts)) * 100)

cat(paste("\nTotal:", totSparsity))
cat(paste("\nsimulatedSparsity:", simulatedSparsity))
cat(paste("\ntrueSparsity:", trueSparsity))

# Add gene Info
gene.info <- add_gene_anno(sim.sce = sim.sce)
gene.info <- gene.info[mixedsort(gene.info$gene_short_name), ]

# Create Bar
bar.df <- gene.info[, c("status", "status2")]
colnames(bar.df) <- c("DE", "Fold_Change")
bar.df <- as.data.frame(table(bar.df[, c("DE", "Fold_Change")]))
bar.df <- bar.df[bar.df$Freq != 0, ]
bar <- ggplot(bar.df, aes(x = DE, y = Freq, fill = Fold_Change)) +
  geom_bar(stat = "identity", position = "stack") +
  geom_text(aes(label = Freq), position = position_stack(vjust = 0.5), size = 3) +
  theme_minimal() +
  ggtitle("Number of genes in the simulated data",
    subtitle = "Category-wise distribution"
  ) +
  labs(x = "DE", y = "Frequency", fill = "Fold Change") +
  theme(legend.position = "bottom")

# Update the SCE Simulated Object
rowData(sim.sce) <- DataFrame(gene.info)

# Write object
obj.path <- paste0(rdsPath, paste0("testTradeSeq.RData"))
save(sim.sce, file = obj.path)

# Compute UMAP Dimensions
sob <- CreateSeuratObject(
  counts = sim.sce@assays@data@listData$counts,
  meta.data = as.data.frame(sim.sce@colData)
)
sob <- NormalizeData(sob,
  normalization.method = "LogNormalize",
  scale.factor = 10000, verbose = F
)
sob <- FindVariableFeatures(sob,
  selection.method = "vst", nfeatures = 2000,
  verbose = F
)
sob <- ScaleData(sob, verbose = F)
sob <- RunPCA(sob, features = VariableFeatures(object = sob), verbose = F)
sob <- RunUMAP(sob, dims = 1:10, verbose = F)

# Create Plotting frame for PHATE
plt.data <- data.frame(
  UMAP_1 = sob@reductions[["umap"]]@cell.embeddings[, 1],
  UMAP_2 = sob@reductions[["umap"]]@cell.embeddings[, 2],
  Simulated_Steps = sim.sce@colData$Step,
  Path = sim.sce@colData$Group
)

plt <- ggplot(plt.data) +
  geom_point(
    aes(
      x = UMAP_1,
      y = UMAP_2,
      color = Simulated_Steps,
      shape = Path
    ),
    size = 1.5
  ) +
  theme_minimal(base_size = 12) +
  scale_color_viridis(option = "C") +
  ggtitle(
    paste(
      "Total Sparsity:", totSparsity, "(38 + 22)"
    ),
    subtitle = paste("Lengths (Path1> Path2), Skewness (Path-1: Start, Path-2: End)")
  ) +
  theme(legend.position = "bottom")
plt

combine <- ggarrange(plt, bar, labels = c("A.", "B."), nrow = 1)

# Save the plot
ggsave(
  plot = combine,
  filename = paste0(figPath_hd, "04_tradeSeq_Sim.png"),
  dpi = 600, width = 12, height = 6
)
ggsave(
  plot = combine,
  filename = paste0(figPath_lr, "04_tradeSeq_Sim.png"),
  dpi = 150, width = 12, height = 6
)
