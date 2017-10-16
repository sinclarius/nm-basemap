zip/srtm_%.zip:
	@# 90-meter SRTM tiles
	@mkdir -p $(dir $@)
	@curl -sS -o $@.download 'http://srtm.csi.cgiar.org/SRT-ZIP/SRTM_V41/SRTM_Data_GeoTiff/$(notdir $@)'
	@mv $@.download $@

# Unzip
shp/ne_10m_populated_places.shp: zip/ne_10m_populated_places.zip
	@mkdir -p $(dir $@)
	@rm -rf tmp && mkdir tmp
	@unzip -q -o -d tmp $<
	@cp tmp/* $(dir $@)
	@rm -rf tmp

shp/cb_2016_35_bg_500k.shp:
	@mkdir -p $(dir $@)
	@rm -rf tmp && mkdir tmp
	@unzip -q -o -d tmp zip/cb_2016_35_bg_500k.zip
	@rm -rf tmp/__MACOSX
	@cp tmp/* $(dir $@)
	@rm -rf tmp

tif/srtm_%.tif: zip/srtm_%.zip
	@mkdir -p $(dir $@)
	@rm -rf tmp && mkdir tmp
	@unzip -q -o -d tmp $<
	@cp tmp/* $(dir $@)
	@rm -rf tmp

# Merge topographic tiles.
# Use http://dwtkns.com/srtm/ to find which tiles are needed.
tif/nm-merged-90m.tif: \
	tif/srtm_15_05.tif \
	tif/srtm_15_06.tif \
	tif/srtm_16_05.tif \
	tif/srtm_16_06.tif 

	@mkdir -p $(dir $@)
	@gdal_merge.py \
		-o $@ \
		-init "255" \
		tif/srtm_*.tif

# Convert to Mercator
tif/nm-reprojected.tif: tif/nm-merged-90m.tif
	@# Comes as WGS 84 (EPSG:4326). Want Mercator (EPSG:3857) for D3 projection.
	@mkdir -p $(dir $@)
	@gdalwarp \
		-co "TFW=YES" \
		-s_srs "EPSG:4326" \
		-t_srs "EPSG:3857" \
		$< \
		$@

# Crop raster to shape of NM
tif/nm-cropped.tif: tif/nm-reprojected.tif
	@mkdir -p $(dir $@)
	@gdalwarp \
		-cutline shp/cb_2016_35_bg_500k.shp \
		-crop_to_cutline \
		-dstalpha $< $@

# Shade and color
tif/nm-color-crop.tif: tif/nm-cropped.tif
	@rm -rf tmp && mkdir -p tmp
	@gdaldem \
		hillshade \
		$< tmp/hillshade.tmp.tif \
		-z 5 \
		-az 315 \
		-alt 60 \
		-compute_edges
	@gdal_calc.py \
		-A tmp/hillshade.tmp.tif \
		--outfile=$@ \
		--calc="255*(A>220) + A*(A<=220)"
	@gdal_calc.py \
		-A tmp/hillshade.tmp.tif \
		--outfile=tmp/opacity_crop.tmp.tif \
		--calc="1*(A>220) + (256-A)*(A<=220)"
	@rm -rf tmp

# Convert to .png
nm.png: tif/nm-color-crop.tif
	@convert \
		-resize x1340 \
		$< $@
