# Appliance changes to the pinned shim

The resolver still verifies the original wheel against the hash-pinned source.
After installation, `apply_appliance_patches` applies `tv-scale.json` with exact
whole-file SHA-256 checks before and after the change. No fuzzy matching or
unverified upstream download is permitted. Rebase and review the patch when
updating the dependency pin. Installed provenance is recorded in
`appliance-patches.json` and the bundle SBOM.

The shim's desktop default uses the compositor's HiDPI factor. A television
can report 1x at both 1080p and 4K, making the latter UI too small. The appliance
instead resolves automatic scaling from the initial renderer viewport, fitting
a 1280x720 logical canvas using both axes. Explicit Interface Scale and `--scale`
values win. This uses the shim's existing scaling boundary for layout, artwork,
text and pointer coordinates, rather than scaling only the rendered picture.

The scale is chosen once when the renderer is ready, matching upstream's bitmap
cache lifecycle. Restart the app after changing HDMI resolution; this patch does
not implement live cache rebuilding. The viewport comes from the renderer, not
an EDID list of supported modes or video dimensions.
