%% test_stage2_probabilities_mesh_20260722.m
% Focused QC script (07/22/2026; machinery removed 07/27/2026): render a
% side-by-side comparison of the tp=1 mesh built from Haibei's ORIGINAL
% ilastik probabilities vs. the retrained "Stage 2" probabilities.
%
% The original backup -> swap -> recompute -> restore workflow that
% generated the two meshes has been REMOVED now that both results are
% safely backed up on disk. This script is therefore now purely read-only
% with respect to the dataset: it never overwrites any probabilities file,
% never calls getMeshes(), and never writes to the mesh backup folders. It
% only:
%   1. Inspects tp=1's cached-mesh state and where getMeshes() reads its
%      probabilities from (read-only, for reference).
%   2. Loads the two already-generated raw MorphSnakes meshes straight from
%      the backup folder and renders per-z-slice QC overlays comparing them
%      (Questions 4/5/6). The only things written are the QC image folders.
clear; close all; clc;
cd /mnt/data/to_deconvolve/haibei/2024-12-14_214253_48YGAL4_UASmChCAAX_UASnlsGFP/unpacked_cropped/
dataDir = cd ;
%% ADD PATHS TO THIS ENVIRONMENT
addpath(genpath('/mnt/data/code/haibei/tubular_related/matlab'))
addpath(genpath('/mnt/data/code/haibei/tubular'))
addpath(genpath('/mnt/data/code_static/matlab/plotting/'))
addpath(genpath('/mnt/data/code_static/matlab/tiff_handling/'))
disp('Loading masterSettings from ./masterSettings.mat')
load('./masterSettings.mat', 'masterSettings')
dataDir = fullfile(dataDir, 'deconvolved_16bit');
cd(dataDir)
%% Load xp/opts and construct tubi
disp('loading xp struct from disk')
load(fullfile(dataDir, 'xp.mat'), 'xp', 'opts')
disp('defining TubULAR class instance (tubi = tubular instance)')
tubi = TubULAR(xp, opts) ;
disp('done defining TubULAR instance')
tubi.xp.expMeta.channelsUsed=[1,2]; %added [1,2]
%% Look at axes order -- reading the Stage 2 file (read-only)
% Confirms the Stage 2 probabilities file has the expected/consistent
% dimensions before trusting anything downstream.
Tp_example = h5read([dataDir, '/Time_000000_cxyz.h5'], '/inputData');
% FIX 07/22/2026: was lowercase 'time_...' -- Linux is case-sensitive and
% the actual file on disk is capitalized 'Time_...' (confirmed via the
% file browser Properties dialog), causing "File or folder not found."
stage2ProbFile = '/mnt/data/zeyuzhao/probabilities/Time_000001_cxyz_Probabilities Stage 2.h5';
% NOTE: assumes dataset name '/exported_data' (standard ilastik convention,
% same as Haibei's export) -- if this errors, run
% h5disp(stage2ProbFile) to find the actual dataset name and fix below.
Tp_prob = h5read(stage2ProbFile, '/exported_data');
[cnum, xpix, ypix, zpix] = size(Tp_example);
axesPixels = struct();
if xpix==ypix || ypix==zpix || zpix==xpix
   disp('Some axes have same pixel numbers. Add some pixel with 0 value to make them different');
else
   axesPixels.xpix = xpix; axesPixels.ypix = ypix;
   axesPixels.zpix = zpix; axesPixels.cnum = cnum;
   fprintf('x axis: %d pixels. y axis: %d pixels. z axis: %d pixels. %d channels.\n', ...
       xpix, ypix, zpix, cnum);
end
tubi.axesPixels = axesPixels;
tubi.axes_pixels_list = [xpix, ypix, zpix, cnum];
fprintf('Stage 2 probabilities file shape check:\n')
fprintf('  size(Tp_prob) = %s\n', mat2str(size(Tp_prob)))
fprintf('  (compare against a known-good Haibei Probabilities.h5 shape if unsure)\n')
%% QUESTION 1: does tp=1 already have a cached mesh?
mesh_tp1_fn = sprintf(tubi.fullFileBase.mesh, 1) ;
mesh_tp1_exists = exist(mesh_tp1_fn, 'file') == 2 ;
fprintf('\nMesh for tp=1 already exists on disk: %d (2=yes, 0=no)\n', mesh_tp1_exists*2)
disp(mesh_tp1_fn)
%% QUESTION 2: where does getMeshes() actually look for probabilities?
disp(' ')
disp('tubi.fileName struct (separate from tubi.dir/fullFileBase):')
disp(tubi.fileName)
disp('tubi.dir.data (base folder getMeshes may read Probabilities.h5 from directly):')
disp(tubi.dir.data)
% CONFIRMED 07/22/2026: tubi.fileName has NO probabilities/ilastik field at
% all (fields are t0, apdvOptions, apBoundaryDorsalPts, ..., writhe,
% features, pivRaw, pathlines, pivAvg -- none related). tubi.dir.data is
% exactly dataDir. This confirms getMeshes() reads
% 'Time_%06d_Probabilities.h5' hardcoded directly out of tubi.dir.data --
% there is NO redirectable property for this. (This is why the original
% test had to physically place the Stage 2 file at the canonical path; that
% swap workflow has since been removed -- see the header note.)
try
   canonicalProbFn = sprintf(tubi.fullFileBase.probabilities, 1);
catch
   canonicalProbFn = fullfile(dataDir, sprintf('Time_%06d_Probabilities.h5', 1));
end
fprintf('Canonical probabilities path for tp=1: %s\n', canonicalProbFn)
%% Locate the two already-generated raw MorphSnakes meshes (read-only)
% Both meshes were produced by the (now-removed) swap-recompute workflow and
% backed up here. This script loads them directly -- it does not regenerate
% them, and it does not write to this folder.
rawMeshBackupDir = '/mnt/data/zeyuzhao/mesh_ms_backup_before_stage2_test';
rawMeshBackupFn_stage2   = fullfile(rawMeshBackupDir, sprintf('mesh_ms_%06d_stage2.ply', 1));
rawMeshBackupFn_original = fullfile(rawMeshBackupDir, sprintf('mesh_ms_%06d_original.ply', 1));
if ~exist(rawMeshBackupFn_stage2, 'file')
   error('Stage 2 backup mesh not found: %s', rawMeshBackupFn_stage2)
end
if ~exist(rawMeshBackupFn_original, 'file')
   error('Original backup mesh not found: %s', rawMeshBackupFn_original)
end
fprintf('Stage 2 mesh:  %s\n', rawMeshBackupFn_stage2)
fprintf('Original mesh: %s\n', rawMeshBackupFn_original)
%% QUESTION 4: mesh check for tp=1 (Stage 2 probabilities), ALL z-slices
% Loads the already-generated Stage 2 raw MorphSnakes mesh from the backup
% folder (read-only) and renders per-z-slice contour overlays. Same QC
% pipeline as script_midgut_20241214_...m's "Evaluate the quality of the
% mesh" section: axis-1 slicing, tuned LUT clipping (loPct=80/hiPct=99.9),
% and the sorted+closed contour overlay -- scoped to this one test timepoint.
stage2CheckSaveDir = '/mnt/data/zeyuzhao/mesh_check_stage2_test';
if ~exist(stage2CheckSaveDir, 'dir')
   mkdir(stage2CheckSaveDir)
end
tubi.setTime(1) ;
% NOTE: if read_ply_mod is not found on your path, use whichever PLY
% reader is available in this environment instead -- it just needs to
% return a struct with .f (faces) and .v (vertices) fields.
mesh_stage2Check = read_ply_mod(rawMeshBackupFn_stage2) ;
IV_stage2Check = tubi.getCurrentData() ;

tubi.normalShift = 7;
zthickness_stage2Check = 5 ;
loPct0_stage2 = 80 ;   hiPct0_stage2 = 99.9 ;
loPct1_stage2 = 80 ;   hiPct1_stage2 = 99.9 ;
for zidx = 1:10:size(IV_stage2Check{1}, 1)
   implane0 = squeeze(IV_stage2Check{1}(zidx,:,:)) ;
   implane1 = squeeze(IV_stage2Check{2}(zidx,:,:)) ;
   lo0 = prctile(double(implane0(:)), loPct0_stage2) ;
   hi0 = prctile(double(implane0(:)), hiPct0_stage2) ;
   lo1 = prctile(double(implane1(:)), loPct1_stage2) ;
   hi1 = prctile(double(implane1(:)), hiPct1_stage2) ;
   implane0 = mat2gray(double(implane0), [lo0 hi0]) ;
   implane1 = mat2gray(double(implane1), [lo1 hi1]) ;
   rgbim = cat(3, implane0, implane1, implane0) ;
   clf
   imshow(rgbim);
   hold on;
   inslab = find(abs(mesh_stage2Check.v(:, 1) - zidx) < zthickness_stage2Check) ;
   if isempty(inslab)
       warning('tp=1 (Stage 2 mesh), z=%d: no mesh vertices within zthickness -- no contour to plot.', zidx)
   else
       slabY = mesh_stage2Check.v(inslab, 2);
       slabZ = mesh_stage2Check.v(inslab, 3);
       centroidYZ = [mean(slabY), mean(slabZ)];
       angles = atan2(slabZ - centroidYZ(2), slabY - centroidYZ(1));
       [~, sortOrder] = sort(angles);
       slabY = slabY(sortOrder);
       slabZ = slabZ(sortOrder);
       slabY(end+1) = slabY(1);   %#ok<AGROW>  % close the loop
       slabZ(end+1) = slabZ(1);   %#ok<AGROW>
       plot(slabZ, slabY, '-o', 'Color', 'blue', 'LineWidth', 2, ...
           'MarkerSize', 4, 'MarkerFaceColor', 'blue')
   end
   title(sprintf('tp=1 (Stage 2 probabilities mesh), z=%d', zidx))
   outfn = fullfile(stage2CheckSaveDir, sprintf('tp_000001_z_%04d.png', zidx));
   saveas(gcf, outfn)
end
disp(['Stage 2 mesh check images saved to: ', stage2CheckSaveDir])
%% QUESTION 5: mesh check for tp=1's OLD (Haibei's-probabilities) mesh
% Same QC pipeline as Question 4, but loads the ORIGINAL raw mesh
% (mesh_ms_000001_original.ply) from the backup folder via read_ply_mod.
% Saves to a SEPARATE folder so old vs. new outputs never collide.
oldMeshCheckSaveDir = '/mnt/data/zeyuzhao/mesh_check_original_test';
if ~exist(oldMeshCheckSaveDir, 'dir')
   mkdir(oldMeshCheckSaveDir)
end
% NOTE: if read_ply_mod is not found on your path, use whichever PLY
% reader is available in this environment instead (e.g. gptoolbox's
% readOBJ/readPLY, or MATLAB's built-in pcread/stlread if applicable) --
% it just needs to return a struct with .f (faces) and .v (vertices)
% fields, same shape as mesh_stage2Check.
mesh_oldCheck = read_ply_mod(rawMeshBackupFn_original) ;
% Concrete check that the two meshes are actually different, before
% spending time rendering z-slices. Vertex/face COUNT differing is the
% simplest, strongest evidence -- MorphSnakes re-run on a different
% probability map will essentially never produce the exact same mesh
% topology. isequal() gives an absolute yes/no; if sizes happen to match,
% the max-difference number tells you HOW different (a few pixels of
% shift vs. a wildly different surface).
fprintf('\n--- Comparing new (Stage 2) vs old (original) mesh ---\n')
fprintf('New mesh:  %d vertices, %d faces\n', size(mesh_stage2Check.v,1), size(mesh_stage2Check.f,1))
fprintf('Old mesh:  %d vertices, %d faces\n', size(mesh_oldCheck.v,1), size(mesh_oldCheck.f,1))
if isequal(size(mesh_stage2Check.v), size(mesh_oldCheck.v))
   identicalVerts = isequal(mesh_stage2Check.v, mesh_oldCheck.v);
   fprintf('Vertex arrays identical (isequal): %d\n', identicalVerts)
   if ~identicalVerts
       fprintf('Max per-coordinate difference: %g\n', max(abs(mesh_stage2Check.v(:) - mesh_oldCheck.v(:))))
   end
else
   disp('Vertex counts differ -- meshes are structurally different (cannot do element-wise comparison, and do not need to: different vertex counts alone proves they differ).')
end
if isequal(mesh_stage2Check.v, mesh_oldCheck.v) && isequal(mesh_stage2Check.f, mesh_oldCheck.f)
   warning(['New and old backup meshes are EXACTLY IDENTICAL. This would mean the ', ...
       'Stage 2 probabilities produced an identical result to Haibei''s original ', ...
       '(unlikely) -- or that the two backup files are actually copies of the same ', ...
       'mesh. Double-check the backup files before trusting the QC images below.'])
else
   disp('Confirmed: new and old meshes differ. Proceeding to render QC comparison images.')
end
% IV is unchanged from Question 4 (same raw image data at tp=1 -- only the
% mesh differs between old/new, not the underlying image volume), so
% IV_stage2Check can be reused directly here.
for zidx = 1:10:size(IV_stage2Check{1}, 1)
   implane0 = squeeze(IV_stage2Check{1}(zidx,:,:)) ;
   implane1 = squeeze(IV_stage2Check{2}(zidx,:,:)) ;
   lo0 = prctile(double(implane0(:)), loPct0_stage2) ;
   hi0 = prctile(double(implane0(:)), hiPct0_stage2) ;
   lo1 = prctile(double(implane1(:)), loPct1_stage2) ;
   hi1 = prctile(double(implane1(:)), hiPct1_stage2) ;
   implane0 = mat2gray(double(implane0), [lo0 hi0]) ;
   implane1 = mat2gray(double(implane1), [lo1 hi1]) ;
   rgbim = cat(3, implane0, implane1, implane0) ;
   clf
   imshow(rgbim);
   hold on;
   inslab = find(abs(mesh_oldCheck.v(:, 1) - zidx) < zthickness_stage2Check) ;
   if isempty(inslab)
       warning('tp=1 (ORIGINAL mesh), z=%d: no mesh vertices within zthickness -- no contour to plot.', zidx)
   else
       slabY = mesh_oldCheck.v(inslab, 2);
       slabZ = mesh_oldCheck.v(inslab, 3);
       centroidYZ = [mean(slabY), mean(slabZ)];
       angles = atan2(slabZ - centroidYZ(2), slabY - centroidYZ(1));
       [~, sortOrder] = sort(angles);
       slabY = slabY(sortOrder);
       slabZ = slabZ(sortOrder);
       slabY(end+1) = slabY(1);   %#ok<AGROW>  % close the loop
       slabZ(end+1) = slabZ(1);   %#ok<AGROW>
       plot(slabZ, slabY, '-o', 'Color', 'red', 'LineWidth', 2, ...
           'MarkerSize', 4, 'MarkerFaceColor', 'red')
   end
   title(sprintf('tp=1 (ORIGINAL, Haibei''s probabilities mesh), z=%d', zidx))
   outfn = fullfile(oldMeshCheckSaveDir, sprintf('tp_000001_z_%04d.png', zidx));
   saveas(gcf, outfn)
end
disp(['Original mesh check images saved to: ', oldMeshCheckSaveDir])
disp('Compare mesh_check_stage2_test/ (blue contour, new) against mesh_check_original_test/ (red contour, old) for the same z-slices.')
%% QUESTION 6: overlay BOTH contours on the same image, same z-slices
% Easier to spot the actual shift at a glance than flipping between two
% separate folders -- same background/LUT as Questions 4/5, but both
% mesh_stage2Check (blue, new mesh_ms from Stage 2 probabilities) and
% mesh_oldCheck (red, original mesh_ms from Haibei's probabilities)
% contours drawn on top of the SAME image.
overlayCheckSaveDir = '/mnt/data/zeyuzhao/mesh_check_overlay_comparison';
if ~exist(overlayCheckSaveDir, 'dir')
   mkdir(overlayCheckSaveDir)
end
for zidx = 1:10:size(IV_stage2Check{1}, 1)
   implane0 = squeeze(IV_stage2Check{1}(zidx,:,:)) ;
   implane1 = squeeze(IV_stage2Check{2}(zidx,:,:)) ;
   lo0 = prctile(double(implane0(:)), loPct0_stage2) ;
   hi0 = prctile(double(implane0(:)), hiPct0_stage2) ;
   lo1 = prctile(double(implane1(:)), loPct1_stage2) ;
   hi1 = prctile(double(implane1(:)), hiPct1_stage2) ;
   implane0 = mat2gray(double(implane0), [lo0 hi0]) ;
   implane1 = mat2gray(double(implane1), [lo1 hi1]) ;
   rgbim = cat(3, implane0, implane1, implane0) ;
   clf
   imshow(rgbim);
   hold on;
   % New (Stage 2) mesh -- blue
   inslabNew = find(abs(mesh_stage2Check.v(:, 1) - zidx) < zthickness_stage2Check) ;
   haveNew = ~isempty(inslabNew);
   if haveNew
       slabY = mesh_stage2Check.v(inslabNew, 2);
       slabZ = mesh_stage2Check.v(inslabNew, 3);
       centroidYZ = [mean(slabY), mean(slabZ)];
       angles = atan2(slabZ - centroidYZ(2), slabY - centroidYZ(1));
       [~, sortOrder] = sort(angles);
       slabY = slabY(sortOrder); slabZ = slabZ(sortOrder);
       slabY(end+1) = slabY(1); slabZ(end+1) = slabZ(1); %#ok<AGROW>
       hNew = plot(slabZ, slabY, '-o', 'Color', 'blue', 'LineWidth', 2, ...
           'MarkerSize', 4, 'MarkerFaceColor', 'blue');
   end
   % Old (original) mesh -- red
   inslabOld = find(abs(mesh_oldCheck.v(:, 1) - zidx) < zthickness_stage2Check) ;
   haveOld = ~isempty(inslabOld);
   if haveOld
       slabY = mesh_oldCheck.v(inslabOld, 2);
       slabZ = mesh_oldCheck.v(inslabOld, 3);
       centroidYZ = [mean(slabY), mean(slabZ)];
       angles = atan2(slabZ - centroidYZ(2), slabY - centroidYZ(1));
       [~, sortOrder] = sort(angles);
       slabY = slabY(sortOrder); slabZ = slabZ(sortOrder);
       slabY(end+1) = slabY(1); slabZ(end+1) = slabZ(1); %#ok<AGROW>
       % CHANGED: dashed line style (not just color) so a near-perfect
       % overlap with the blue "new" contour still shows visibly as
       % "solid blue with red dashes on top", instead of solid red fully
       % masking blue when the two contours coincide closely -- makes
       % "both present and very similar" visually distinguishable from
       % "the other one simply isn't there" (check via the legend too).
       hOld = plot(slabZ, slabY, '--o', 'Color', 'red', 'LineWidth', 2, ...
           'MarkerSize', 4, 'MarkerFaceColor', 'red');
   end
   if ~haveNew && ~haveOld
       warning('z=%d: neither mesh has vertices in this slab -- no contours to plot.', zidx)
   elseif haveNew && haveOld
       legend([hNew, hOld], {'new (Stage 2)', 'old (original)'}, 'Location', 'best')
   elseif haveNew
       legend(hNew, {'new (Stage 2)'}, 'Location', 'best')
   else
       legend(hOld, {'old (original)'}, 'Location', 'best')
   end
   title(sprintf('tp=1 overlay: blue=new (Stage 2), red=old (original), z=%d', zidx))
   outfn = fullfile(overlayCheckSaveDir, sprintf('tp_000001_z_%04d.png', zidx));
   saveas(gcf, outfn)
end
disp(['Overlay comparison images saved to: ', overlayCheckSaveDir])
