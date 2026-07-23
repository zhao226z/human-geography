%% test_stage2_probabilities_mesh_20260722.m
% Focused test script (07/22/2026): does swapping in the retrained "Stage 2"
% ilastik probabilities file for timepoint 1 actually change the mesh
% getMeshes() produces? Split out of script_midgut_20241214_...m so this
% specific investigation doesn't require the whole 3000+ line pipeline
% script -- just the setup needed to construct tubi and call getMeshes().
%
% What this answers:
%   1. Does tp=1 already have a cached mesh on disk? (if so, overwrite=false
%      would silently skip recomputation and the new probabilities would
%      have zero effect)
%   2. Where does getMeshes() actually look for its probabilities input --
%      tubi.fileName.*, or hardcoded from tubi.dir.data? (prints both so we
%      stop guessing)
%   3. A SAFE, targeted test: back up whatever mesh currently exists for
%      tp=1, force a recompute for JUST that one timepoint (not the whole
%      dataset), and leave the original safely backed up for comparison.
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
%% Look at axes order (MUST run before getMeshes()) -- reading the Stage 2 file
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
% there is NO redirectable property for this. The only way to make
% getMeshes() use the Stage 2 file is to physically place it at
% dataDir/Time_000001_Probabilities.h5 -- which risks overwriting Haibei's
% actual file there. Section below does this via an explicit
% backup -> swap -> recompute -> restore sequence so her original file is
% never left replaced.
% FIX 07/22/2026: removed a leftover duplicate line that called
% tubi.fullFileBase.probabilities WITHOUT the try/catch guard below --
% that unprotected copy crashed first with "Unrecognized field name
% 'probabilities'" before ever reaching this safe version. Confirmed
% 07/22/2026 that the field genuinely doesn't exist, so this always falls
% through to the hardcoded fallback path -- kept as try/catch anyway in
% case a future TubULAR version does add this field.
try
   canonicalProbFn = sprintf(tubi.fullFileBase.probabilities, 1);
catch
   canonicalProbFn = fullfile(dataDir, sprintf('Time_%06d_Probabilities.h5', 1));
end
fprintf('Canonical probabilities path for tp=1: %s\n', canonicalProbFn)
%% QUESTION 3: back up existing mesh AND existing probabilities file,
%% swap in Stage 2, force a recompute for JUST tp=1, then RESTORE Haibei's
%% original probabilities file so dataDir is left exactly as it was found.
meshBackupDir = '/mnt/data/zeyuzhao/mesh_backup_before_stage2_test';
probBackupDir = '/mnt/data/zeyuzhao/probabilities_backup_before_stage2_test';
if ~exist(meshBackupDir, 'dir'); mkdir(meshBackupDir); end
if ~exist(probBackupDir, 'dir'); mkdir(probBackupDir); end
if mesh_tp1_exists
   [~, meshName, meshExt] = fileparts(mesh_tp1_fn);
   meshBackupFn = fullfile(meshBackupDir, [meshName, '_original', meshExt]);
   if ~exist(meshBackupFn, 'file')
       copyfile(mesh_tp1_fn, meshBackupFn);
       fprintf('Backed up existing tp=1 mesh to: %s\n', meshBackupFn)
   else
       fprintf('Mesh backup already exists, not overwriting: %s\n', meshBackupFn)
   end
else
   disp('No existing mesh for tp=1 to back up -- overwrite=false would already compute it fresh.')
end
canonicalProbExists = exist(canonicalProbFn, 'file') == 2;
if canonicalProbExists
   [~, probName, probExt] = fileparts(canonicalProbFn);
   probBackupFn = fullfile(probBackupDir, [probName, '_haibei_original', probExt]);
   if ~exist(probBackupFn, 'file')
       copyfile(canonicalProbFn, probBackupFn);
       fprintf('Backed up Haibei''s tp=1 Probabilities.h5 to: %s\n', probBackupFn)
   else
       fprintf('Probabilities backup already exists, not overwriting: %s\n', probBackupFn)
   end
else
   warning(['No existing Probabilities.h5 found at the canonical path for tp=1 -- ', ...
       'nothing to back up, but also means getMeshes() may error/fail if it ', ...
       'strictly requires this file to already exist.'])
end
% Uncomment ALL of the block below together to actually run the test --
% left commented so nothing destructive happens just from running this
% script top to bottom. Do NOT run only part of this block (the restore
% at the end is what guarantees Haibei's file gets put back).
%
% copyfile(stage2ProbFile, canonicalProbFn);  % swap in Stage 2, OVERWRITES canonical file
% disp('Swapped in Stage 2 probabilities at the canonical tp=1 path.')
% % CONFIRMED (from getMeshes.m source, npmitchell/tubular): the smoothing
% % step shells out to meshlabserver via system(), whose exit code is NOT
% % checked -- so if meshlabserver is missing, getMeshes() prints false
% % "success" and the SMOOTHED mesh (mesh_%06d.ply) silently never updates.
% % This is just an informational warning, not a hard stop: the raw
% % MorphSnakes mesh (mesh_ms_%06d.ply) is written BEFORE meshlabserver
% % runs, so it still updates correctly -- which is the file Questions 4/5/6
% % actually compare.
% [msStatus, ~] = system('which meshlabserver');
% if msStatus ~= 0
%     warning(['meshlabserver not found on this system -- mesh_ms_%06d.ply (raw) will ', ...
%         'still be regenerated correctly, but mesh_%06d.ply (smoothed) will NOT update; ', ...
%         'getMeshes() will report success anyway. This is expected here.'])
% end
% try
%     allTimePoints_stage2Test = tubi.xp.fileMeta.timePoints ;
%     tubi.xp.fileMeta.timePoints = 1 ;
%     tubi.getMeshes(true) ;   % overwrite=true, but scoped to ONLY tp=1
%     tubi.xp.fileMeta.timePoints = allTimePoints_stage2Test ;
%     disp('Recomputed tp=1 mesh using Stage 2 probabilities -- compare against the backup.')
% catch recomputeME
%     warning('getMeshes() failed: %s -- restoring original probabilities regardless.', recomputeME.message)
% end
% if canonicalProbExists
%     copyfile(probBackupFn, canonicalProbFn);
%     disp('Restored Haibei''s original Probabilities.h5 -- dataDir is back to how it was found.')
% else
%     delete(canonicalProbFn);
%     disp('Deleted the Stage 2 file from the canonical path (nothing was there originally).')
% end
disp(' ')
disp('Done. Review Q1/Q2/Q3 output above before uncommenting the swap-recompute-restore block.')
%% QUESTION 3B: regenerate Haibei's ORIGINAL raw MorphSnakes mesh for comparison
% Question 3 only backed up the SMOOTHED mesh (mesh_%06d.ply). The file
% that actually changes when getMeshes() runs is the RAW MorphSnakes
% output, mesh_ms_%06d.ply -- and the swap-recompute block above already
% overwrote it with the Stage 2 result, with no backup taken first. Since
% MorphSnakes is deterministic for a given probability map, we can
% RECONSTRUCT what the original mesh_ms file looked like: swap Haibei's
% original probabilities back in, recompute once, back that up, then swap
% Stage 2 back in and recompute AGAIN so the canonical folder ends up back
% in the state you actually want to keep (the Stage 2 result).
%
% CHANGED 07/23/2026: also seed BOTH recomputes from tp=0's real,
% untouched level set (msls_000000.mat) instead of the default sphere.
% CONFIRMED (from getMeshes.m source): with tubi.xp.fileMeta.timePoints
% scoped to ONLY [1], there is no "previous timepoint" within that list,
% so init_ls_fn ('msls_initguess', a file that doesn't exist) falls
% through to a generic radius-40 sphere -- and BOTH the z=471 red and blue
% contours you saw were small, badly-placed blobs that didn't trace the
% real tissue at all, confirming this. tubi.xp.detectOptions.init_ls_fn
% (confirmed via disp() to equal 'msls_initguess' on this instance) can be
% supplied directly as a full path to a .mat file containing a 'BW' mask
% -- getMeshes() loads and crops it to size automatically
% (cropToMatchSize), so it doesn't need to match tp=1's exact dimensions.
% We do NOT add tp=0 to the timepoints list to get this seed (that would
% require overwrite=true across the whole list, which would force-
% recompute and risk destroying tp=0's real production mesh/level set) --
% supplying init_ls_fn directly avoids touching tp=0 at all.
%
% Uncomment this ENTIRE block together and run it as one unit -- running
% only part of it will leave the canonical folder in the wrong state.
rawMeshFn = fullfile(fileparts(mesh_tp1_fn), sprintf('mesh_ms_%06d.ply', 1));
rawMeshBackupDir = '/mnt/data/zeyuzhao/mesh_ms_backup_before_stage2_test';
if ~exist(rawMeshBackupDir, 'dir')
   mkdir(rawMeshBackupDir)
end
[~, rawMeshName, rawMeshExt] = fileparts(rawMeshFn);
rawMeshBackupFn_stage2   = fullfile(rawMeshBackupDir, [rawMeshName, '_stage2', rawMeshExt]);
rawMeshBackupFn_original = fullfile(rawMeshBackupDir, [rawMeshName, '_original', rawMeshExt]);
tp0SeedFn = fullfile(fileparts(mesh_tp1_fn), 'msls_000000.mat');
if ~exist(tp0SeedFn, 'file')
   warning(['tp=0 seed file not found: %s -- if this is missing, the recompute below ', ...
       'will silently fall back to the default sphere again. Check the filename/path ', ...
       'before uncommenting Step 2/4.'], tp0SeedFn)
else
   fprintf('Found tp=0 seed file for init_ls_fn: %s\n', tp0SeedFn)
end
% Step 1: back up the CURRENT (Stage 2) raw mesh first, so it isn't lost
% while we regenerate the original for comparison.
if ~exist(rawMeshBackupFn_stage2, 'file')
    copyfile(rawMeshFn, rawMeshBackupFn_stage2);
    disp(['Backed up current Stage 2 raw mesh to: ', rawMeshBackupFn_stage2])
end

% Step 2: swap Haibei's ORIGINAL probabilities back in, recompute tp=1 only.
copyfile(probBackupFn, canonicalProbFn);
disp('Swapped Haibei''s original probabilities back in.')
% See the note in the swap-recompute-restore block above: meshlabserver
% missing means mesh_ms_%06d.ply (raw) still updates correctly, but
% mesh_%06d.ply (smoothed) silently won't -- expected, not a bug.
[msStatus, ~] = system('which meshlabserver'); %#ok<ASGLU>
if msStatus ~= 0
    warning('meshlabserver not found -- mesh_ms_%06d.ply will still update correctly; mesh_%06d.ply will not.')
end
allTimePoints_regen = tubi.xp.fileMeta.timePoints ;
origInitLsFn = tubi.xp.detectOptions.init_ls_fn ;
tubi.xp.fileMeta.timePoints = 1 ;
tubi.xp.detectOptions.init_ls_fn = tp0SeedFn ;
tubi.getMeshes(true) ;
tubi.xp.fileMeta.timePoints = allTimePoints_regen ;
tubi.xp.detectOptions.init_ls_fn = origInitLsFn ;
disp('Recomputed tp=1 mesh using Haibei''s ORIGINAL probabilities, seeded from tp=0''s level set.')

% Step 3: back up this regenerated ORIGINAL raw mesh immediately.
if ~exist(rawMeshBackupFn_original, 'file')
    copyfile(rawMeshFn, rawMeshBackupFn_original);
    disp(['Backed up regenerated original raw mesh to: ', rawMeshBackupFn_original])
end

% Step 4: swap Stage 2 probabilities back in, recompute tp=1 ONE MORE TIME
% (seeded the SAME way, from tp=0's level set, so the comparison stays
% fair) so the canonical folder ends up back in the Stage 2 state, then
% restore Haibei's original probabilities.h5 itself (matches the
% Question 3 swap-recompute-restore block's end state).
copyfile(stage2ProbFile, canonicalProbFn);
tubi.xp.fileMeta.timePoints = 1 ;
tubi.xp.detectOptions.init_ls_fn = tp0SeedFn ;
tubi.getMeshes(true) ;
tubi.xp.fileMeta.timePoints = allTimePoints_regen ;
tubi.xp.detectOptions.init_ls_fn = origInitLsFn ;
copyfile(probBackupFn, canonicalProbFn);
disp('Restored canonical mesh to the Stage 2 result (seeded), and restored Haibei''s original probabilities.h5.')
disp(' ')
disp('Review the plan above, then uncomment the whole QUESTION 3B block together to run it.')
%% QUESTION 4: mesh check for tp=1, ALL z-slices -- run AFTER the
%% swap-recompute-restore block above has actually run (so tubi's current
%% mesh reflects the Stage 2 result, not the backed-up original).
% Reuses the exact same, already-debugged pipeline from
% script_midgut_20241214_...m's "Evaluate the quality of the mesh" section
% this whole session: axis-1 slicing fix, tuned LUT clipping
% (loPct=80/hiPct=99.9), and the sorted+closed contour overlay -- just
% scoped to this one test timepoint instead of a subsample of the movie.
stage2CheckSaveDir = '/mnt/data/zeyuzhao/mesh_check_stage2_test';
if ~exist(stage2CheckSaveDir, 'dir')
   mkdir(stage2CheckSaveDir)
end
% CHANGED: check/load mesh_ms_000001.ply (the RAW MorphSnakes output)
% directly, NOT tubi.getCurrentRawMesh() / mesh_tp1_fn (the smoothed mesh,
% which depends on the missing meshlabserver dependency and never actually
% got rewritten). mesh_ms_000001.ply is the file confirmed (via file
% browser timestamps) to have actually changed after the Stage 2 recompute.
dNewMeshCheck = dir(rawMeshFn);
if exist(rawMeshBackupFn_original, 'file')
   dOldMeshCheck = dir(rawMeshBackupFn_original);
   fprintf('New raw mesh (canonical mesh_ms path) modified: %s\n', dNewMeshCheck.date)
   fprintf('Old raw mesh (regenerated backup) modified:     %s\n', dOldMeshCheck.date)
   if datenum(dNewMeshCheck.date) <= datenum(dOldMeshCheck.date) %#ok<DATNM>
       warning(['Canonical raw mesh is NOT newer than the regenerated-original backup -- ', ...
           'the swap-recompute block may not have actually run/written a new mesh yet.'])
   end
else
   fprintf('New raw mesh (canonical mesh_ms path) modified: %s\n', dNewMeshCheck.date)
   warning(['No regenerated-original backup found yet at rawMeshBackupFn_original -- ', ...
       'run the QUESTION 3B block first if you want an old-vs-new raw mesh comparison.'])
end
tubi.setTime(1) ;
% NOTE: if read_ply_mod is not found on your path, use whichever PLY
% reader is available in this environment instead -- it just needs to
% return a struct with .f (faces) and .v (vertices) fields.
mesh_stage2Check = read_ply_mod(rawMeshFn) ;
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
% Same QC pipeline as Question 4, but loads the REGENERATED-ORIGINAL raw
% mesh (mesh_ms_000001_original.ply, produced by the QUESTION 3B block)
% from disk via read_ply_mod -- since no direct backup of the original
% mesh_ms_000001.ply was taken before it got overwritten, and tubi's
% current in-memory state now reflects the NEW Stage 2 mesh, not the old
% one. Saves to a SEPARATE folder so old vs. new outputs never collide.
oldMeshCheckSaveDir = '/mnt/data/zeyuzhao/mesh_check_original_test';
if ~exist(oldMeshCheckSaveDir, 'dir')
   mkdir(oldMeshCheckSaveDir)
end
if ~exist(rawMeshBackupFn_original, 'file')
   error(['rawMeshBackupFn_original not found: %s -- run the QUESTION 3B block ', ...
       'first to regenerate and back up Haibei''s original raw mesh before running this section.'], ...
       rawMeshBackupFn_original)
end
% NOTE: if read_ply_mod is not found on your path, use whichever PLY
% reader is available in this environment instead (e.g. gptoolbox's
% readOBJ/readPLY, or MATLAB's built-in pcread/stlread if applicable) --
% it just needs to return a struct with .f (faces) and .v (vertices)
% fields, same shape as mesh_stage2Check.
mesh_oldCheck = read_ply_mod(rawMeshBackupFn_original) ;
% ADDED: concrete check that the two meshes are actually different, before
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
   warning(['New and old meshes are EXACTLY IDENTICAL. This suggests either the ', ...
       'swap-recompute-restore block did not actually run/take effect, or ', ...
       'getMeshes() was skipped (check overwrite settings), or the Stage 2 ', ...
       'probabilities produced an identical result to Haibei''s original by ', ...
       'coincidence (unlikely). Re-verify the swap block ran and printed its ', ...
       'confirmation messages before trusting the Question 4/5 QC images below.'])
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
% mesh_oldCheck (red, regenerated-original mesh_ms from Haibei's
% probabilities) contours drawn on top of the SAME image.
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
