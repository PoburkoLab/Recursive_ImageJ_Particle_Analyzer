//** Created by Damon Poburko, Dept. of Molecular & Cellular Physiology,
//   Stanford University, Stanford, California, March 01, 2009 dpoburko@gmail.com
// 
/*
 This macro was created to faciliate the use of the Analyze Particles plugin in Image J on images with widely varying
particle intensity and varying background intensity, where a single threshold is not sufficient to adequately identify ROIs for
further analysis. This macro is provided as is with limited documentation. 

Principle of analysis: The macro runs the Analyze Particles plugin over a series of threshold values. On each run of Analyze  
Particles, those particles that meet the user-defined criteria will be added to a common store. Once a given puncta exceeds 
the maximum size, the puncta at that location will be held in the common store at the last size which was within the selection 
criteria. The macro does have some limitations in its ability to catch or identify dim puncta that are on the shoulder of a much
brighter neighbouring puncta.

Basic Usage:
1. Select Image that you want to anayze. 
2. Run the macro and enter selection criteria to identify puncta. Will require some optimization of settings for varying image types.
3. If you choose to "auto Calc." the values for the lowest threshold value (= mean of ROI + X*SD), you will be promted to choose an
   ROI for your background
4. In Part 4 below, users may want to alter which measurements are recorded in the results table

version 3.3, August 31, 2011
- added option to run a background subtraction prior to finding ROIs
- simplified dialog with dropDown box to choose whether # of steps or step size would be used
- added option to exclude ROIs that fall within a user definable distance from the image edge
- when running in batchmode, the ROI manager is closed during the macro and re-opened at the end. Macro should run faster this way.
version 3.6, September 22, 2011
- removed unneccesary "setAutoThreshold();" in the particle analyzing loop.  
Runs ~5-10x faster on normal images and prevents 2-5x slow-down in background subtracted images
version 3.7 Oct.01, 2011
- added option to run watershed filter on final set of ROIs
- modified variable names to prevent duplicate variable names when recorded with macro recorder
version3.9 Oct. 03, 2012
-cleaned up interface to make more generic for all users
	- removed override of parameters based on file name
	-made user Preset labels more generic
-clean up some issues with extra windows not closing

- v4.0: added capacifty of handle multiple fil extensions
- v4.1: 130612, corrected 130712 - do watershed for each cycle ()
- v4.2: 140226, add drop down list of autothresholding methods for automatic background calculation.
-            140408 - added more parameteres to saved metric
		 - realized and resolved that ROIs excluded from perimeter were still being counted in the ROI metrics text file
		- solved "Mask of..." images not closing
- v4.3: 140409 corrected issue of crash on trying to analyze slice #1 on multislice image.
- v4.4: 140622 - draw contours with each loop
- v4.6: prevent ROIS from merging
- v4.7: performance improvements
- v4.8: add selection of ROIs by aspect ratio
- v4.9.3: replace exclusion by round with solidity
- v4.9.7: changed contours to be filled # of thresholds, s.t. first mask will have highest pixel value
190305 - rename to RIPA - recursive ImageJ Particle Analyzer v1.0
need to add option to specify guassian after USM

*/

macro "RIPA_v1.1" {

requires("1.49d"); 
// May work with versions prior to 1.42l. Runs faster with IJ1.45n5 due to faster deleting and updating of ROI manager
// ==== User Variables Dialog box: ===============================================
//print (call("ij.Prefs.get", "dialogDefaults.stepMethod","# of thresholds"));

// set preferences in dialog drop down lists
if ( call("ij.Prefs.get", "dialogDefaults.stepMethod","# of thresholds") ==  "step size" ) stepMethodArray = newArray( "step size", "# of thresholds");
if ( call("ij.Prefs.get", "dialogDefaults.stepMethod","# of thresholds") ==  "# of thresholds") stepMethodArray = newArray("# of thresholds","step size");
autoThresholdMethod = call("ij.Prefs.get", "dialogDefaults.autoThresholdMethod","none");
//print(autoThresholdMethod);
if (autoThresholdMethod ==  "none") autoThresholdArray = newArray("none", "Default", "Huang", "Intermodes", "IsoData", "IJ_IsoData", "Li", "MaxEntropy", "Mean", "MinError", "Minimum", "Moments", "Otsu", "Percentile", "RenyiEntropy",  "Shanbhag", "Triangle", "Yen");
if ( autoThresholdMethod !=  "none") autoThresholdArray = newArray(autoThresholdMethod, "none", "Default", "Huang", "Intermodes", "IsoData", "IJ_IsoData", "Li", "MaxEntropy", "Mean", "MinError", "Minimum", "Moments", "Otsu", "Percentile", "RenyiEntropy",  "Shanbhag", "Triangle", "Yen");

//checkBox group1
nrows1 = 2;
ncolumns1 = 2;
n1 = nrows1*ncolumns1;
labels1 = newArray("show single threshold", "[svmsk] save mask","thresholds in file names","[svrois] save ROIs & measurements");
defaults1 = newArray(false, call("ij.Prefs.get", "dialogDefaults.saveImages", false),call("ij.Prefs.get", "dialogDefaults.labelWithThresholds", false),call("ij.Prefs.get", "dialogDefaults.saveResults", false));

//checkBox group2
nrows = 1;
ncolumns = 2;
n = nrows*ncolumns;
labels2 = newArray("presets 1", "presets 2");
defaults2 = newArray(false, false);

version = "1.0";
build = "1.0";

// ======generate dialog boix========================
  Dialog.create("RIPA v" + version);
  Dialog.addMessage("THRESHOLD SETTINGS:");
  Dialog.addNumber("[nSDs] #_of_SDs:", parseInt(call("ij.Prefs.get", "dialogDefaults.xStandardDeviations", "3")));  //usually 3
  Dialog.addChoice("[stepMthd] Define # of thresholds", stepMethodArray); 
   Dialog.addToSameRow()
  Dialog.addNumber("[nThrOrSize] step size:", parseInt(call("ij.Prefs.get", "dialogDefaults.nThresholdsOrStepSize", "20")));
  //Dialog.addMessage("Intensity of 1st threshold and background:");
  Dialog.addNumber(" [UMT] 1st threshold (-1=max)", parseInt(call("ij.Prefs.get", "dialogDefaults.maxPixel", "-1")));
     Dialog.addToSameRow()
  Dialog.addNumber(" [LMT] background (-1 = select ROI)", parseInt(call("ij.Prefs.get", "dialogDefaults.floorPixel", "-1")));
  Dialog.addChoice("[TRMTD] OR IJ autothresholds ('none' = off) ", autoThresholdArray); 
  Dialog.addMessage("PUNCTA PARAMETERS:");
  Dialog.addNumber("[minPS] min puncta size :", parseInt(call("ij.Prefs.get", "dialogDefaults.minParticle", "4")),0,7,"px");
  Dialog.addToSameRow()
  Dialog.addNumber("[maxPS] max :", parseInt(call("ij.Prefs.get", "dialogDefaults.maxParticle", "40")),0,7,"px");
  Dialog.addNumber("[minCirc] min circularity (0.00-1.00):", parseFloat(call("ij.Prefs.get", "dialogDefaults.minCircularity", "0.6")),2,5,"");
  Dialog.addToSameRow()
  Dialog.addNumber("[maxCirc] max:", parseFloat(call("ij.Prefs.get", "dialogDefaults.maxCircularity", "1.0")),2,5,"");
  Dialog.addNumber("[minSolidity] min Solidity (0.00-1.00):", parseFloat(call("ij.Prefs.get", "dialogDefaults.minSolidity", "0.0")),2,5,"");
  Dialog.addToSameRow()
  Dialog.addNumber("[maxSolidity] max Solidiy:", parseFloat(call("ij.Prefs.get", "dialogDefaults.maxSolidity", "1.0")),2,5,"");
  Dialog.addMessage("Pre- & Post- processing options:");
  Dialog.addNumber("[bgSub] background subtraction ballSize (-1 = none):", parseInt(call("ij.Prefs.get", "dialogDefaults.ballSize", "-1")));
  Dialog.addNumber("[usmsz] unsharp mask: size (-1 = none):", parseInt(call("ij.Prefs.get", "dialogDefaults.usmSize", "-1")));
  Dialog.addToSameRow()
  Dialog.addNumber("[usmwt] weight (0-0.9):", parseFloat(call("ij.Prefs.get", "dialogDefaults.usmWeight", "0.6")));
  Dialog.addCheckbox("[wtshd] Watershed: on each loop", call("ij.Prefs.get", "dialogDefaults.doWatershed", false));
  Dialog.addToSameRow()
  Dialog.addCheckbox("[wtshdFinal] last loop", call("ij.Prefs.get", "dialogDefaults.doWatershedFinal", false));
  Dialog.addNumber("exclude ROIs < x pixels from edges: ",parseInt(call("ij.Prefs.get", "dialogDefaults.borderWidth", "5")));
//Dialog.addCheckbox("[cntrs] draw contours plots on ROIs", call("ij.Prefs.get", "dialogDefaults.drawContours", false));
  Dialog.addCheckbox("[nomrg] prevent ROIs from coalescing", call("ij.Prefs.get", "dialogDefaults.noMerging", false));
  Dialog.addMessage("File Handling:");
  Dialog.addCheckboxGroup(nrows1,ncolumns1,labels1,defaults1);
  Dialog.addCheckbox("[called] Set true if calling from another macro.", false);
  Dialog.show();

timeStart = getTime();

// ====== retireve values ============================
xStandardDeviations = Dialog.getNumber();			call("ij.Prefs.set", "dialogDefaults.xStandardDeviations", xStandardDeviations);
stepMethod = Dialog.getChoice();					call("ij.Prefs.set", "dialogDefaults.stepMethod", stepMethod);	
nThresholdsOrStepSize =  Dialog.getNumber();		call("ij.Prefs.set", "dialogDefaults.nThresholdsOrStepSize", nThresholdsOrStepSize);
maxPixel = Dialog.getNumber();						call("ij.Prefs.set", "dialogDefaults.maxPixel", maxPixel);
floorPixel = Dialog.getNumber();					call("ij.Prefs.set", "dialogDefaults.floorPixel", floorPixel);
autoThresholdMethod = Dialog.getChoice();   		call("ij.Prefs.set", "dialogDefaults.autoThresholdMethod", autoThresholdMethod);	
minParticle = Dialog.getNumber();					call("ij.Prefs.set", "dialogDefaults.minParticle", minParticle);
maxParticle = Dialog.getNumber();					call("ij.Prefs.set", "dialogDefaults.maxParticle", maxParticle);
minCircularity = Dialog.getNumber();				call("ij.Prefs.set", "dialogDefaults.minCircularity", minCircularity);
maxCircularity = Dialog.getNumber();				call("ij.Prefs.set", "dialogDefaults.maxCircularity", maxCircularity);
minSolidity = Dialog.getNumber(); 			 			call("ij.Prefs.set", "dialogDefaults.minSolidity", minSolidity);
maxSolidity = Dialog.getNumber(); 			 			call("ij.Prefs.set", "dialogDefaults.maxSolidity", maxSolidity);
ballSize = Dialog.getNumber();						call("ij.Prefs.set", "dialogDefaults.ballSize", ballSize);
	if (ballSize != -1) run("Subtract Background...", "rolling="+ballSize+"");
usmSize = Dialog.getNumber();
						call("ij.Prefs.set", "dialogDefaults.usmSize", usmSize);
usmWeight = Dialog.getNumber();
						call("ij.Prefs.set", "dialogDefaults.usmWeight", usmWeight);
	if (usmSize != -1) run("Unsharp Mask...", "radius="+usmSize+" mask="+usmWeight+" slice");
	
doWatershed =Dialog.getCheckbox();					call("ij.Prefs.set", "dialogDefaults.doWatershed", doWatershed);
doWatershedFinal =Dialog.getCheckbox();					call("ij.Prefs.set", "dialogDefaults.doWatershedFinal", doWatershedFinal);
borderWidth = Dialog.getNumber();					call("ij.Prefs.set", "dialogDefaults.borderWidth", borderWidth);
//drawContours = Dialog.getCheckbox(); 				call("ij.Prefs.set", "dialogDefaults.drawContours", drawContours);
noMerging = Dialog.getCheckbox();					call("ij.Prefs.set", "dialogDefaults.noMerging", noMerging);

doSimpleThreshold = Dialog.getCheckbox();
saveImages  = Dialog.getCheckbox();					call("ij.Prefs.set", "dialogDefaults.saveImages", saveImages);
labelWithThresholds = Dialog.getCheckbox();			call("ij.Prefs.set", "dialogDefaults.labelWithThresholds", labelWithThresholds);
saveResults = Dialog.getCheckbox();					call("ij.Prefs.set", "dialogDefaults.saveResults", saveResults);
calledFromAnotherMacro = Dialog.getCheckbox();

drawContours = false;

//doWatershedFinal = true ; 


startedInBatchMode = false;
if (is("Batch Mode")) startedInBatchMode = true;

if ( (startedInBatchMode == true)&&(calledFromAnotherMacro==false) ) print("started in batch mode");
if (calledFromAnotherMacro==false) print("\\Clear");  	//clear log

// ===================================================================================================   
// ===== Part 2: get image path info & start analysis  ===========================================================    
// ===================================================================================================   
imageHasPath = true; 
imagePath = getDirectory("image");

if (imagePath == "") {
	imageHasPath = false; 
	imagePath = getDirectory("home")  + "imagejTemp"+ File.separator;
	if (File.isDirectory(imagePath)==false) File.makeDirectory(imagePath);
}


setBatchMode(true); 

	//130522 v4.0b: set background to light to allow Watershed to work
	run("Options...", "iterations=1 count=1 edm=Overwrite do=Nothing");

	// **** ROI list manipulation runs much faster when the ROI manager is closed and in BatchMode ****
	if (isOpen("ROI Manager")) {
		roiManager("Reset"); 
	}


	originalName = getTitle();
	
	if (indexOf(originalName," ") == -1) imageName = originalName;
	if (indexOf(originalName," ") != -1) imageName = replace(originalName, " ", "_");

	selectWindow(originalName);
	run("Select None");

	rename(imageName);
	//print(originalName + " renamed as " + imageName);
               baseName = getBaseName(imageName);         	// 130518: v4.0: added functionality to handle .lsm, .jpeg
	fileExtension = getFileExtension(imageName);         	// 130518: v4.0: added functionality to handle .lsm, .jpeg
	suffix = "multThrld";
	getDimensions(width, height, channels, slices, frames);
	w = width;
	h = height;
	Stack.getPosition(channel, slice, frame);
	if (slices ==1)                                                   z="";
	if ((1< slices) && (1<= slice) && (slice<10))   z = "_Z0"+ toString(slice,0);
	if ((1<slices) && (slice>=10) )                        z = "_Z"+ toString(slice,0) + "_";
	if (channels ==1)                                              c="";
	if (channels >1)                                                c = "_C"+toString(channel,0);
	thresholds = "";

	// start building final name with some dummies
	finalName = baseName + "_" + suffix + thresholds + z + c;
	run("Duplicate...", "title=working");
	run("Set Scale...", "distance=0 known=0 pixel=1 unit=pixel");                  // 130521 v4.0: handles images with a defined pixel scale. Removes scale from copie image
	run("Gaussian Blur...", "sigma=0.90");
	getStatistics(area, mean, min, max, std);
	SD = std;

	if (drawContours == true) {
		imgContours = baseName +"_Countours";
		newImage(imgContours, "16-bit white", w, h, 1);
	}

	// ===== determine maximum pixel intensity ===========
	if (maxPixel == -1) {
            		maxPixel = max;
	}

 	// ===== determine background fluorescence ==========
        if ( (floorPixel == -1) && (autoThresholdMethod == "none") ) {
			selectWindow(imageName);
			run("Enhance Contrast", "saturated=0.5");
			waitForUser("Select representative background ROI \n then click OK to resume");
			getStatistics(area, mean, min, max, std);
			SD = round(std);
	        floorPixel = mean + (xStandardDeviations * SD);
			run("Select None");
        }
        if ( (floorPixel == -1) && (autoThresholdMethod != "none") ) {
			if (calledFromAnotherMacro==false) print("using autothreshold");
			setAutoThreshold(autoThresholdMethod+" dark");
			getThreshold(lower, upper); 
			floorPixel = lower;
			if (calledFromAnotherMacro==false) print("floor pixel calculated to be: " + lower);
			resetThreshold;
		}
	selectWindow("working");                                                

// ===================================================================================================   
// ====== Part 3: Calculate step size and fill array from nThresholds or userStepSize ======================================
//=================================================================================================

 	if (stepMethod == "step size") {
           		nThresholds = floor ( abs(maxPixel - floorPixel) / nThresholdsOrStepSize );
		lowerLimits = newArray(nThresholds);
		stepSize = nThresholdsOrStepSize;
		for (k =0; k<lowerLimits.length;k++) {
   			if (maxPixel>floorPixel) tempThresh = (maxPixel - ( (k)* nThresholdsOrStepSize ) );  
   			if (maxPixel<floorPixel) tempThresh = (maxPixel + ( (k)* nThresholdsOrStepSize ) );  
			lowerLimits[k] = tempThresh;   
		}
	} else {
	  	nThresholds = nThresholdsOrStepSize;
		lowerLimits = newArray(nThresholdsOrStepSize);
		nSteps = lowerLimits.length;
		relStep = 1/lowerLimits.length;
		stepSize =  round( (maxPixel - floorPixel) / lowerLimits.length );
		for (k =0; k<lowerLimits.length;k++) {
   	    	if (maxPixel>floorPixel)	tempThresh = round ( ( abs(maxPixel - floorPixel) * ( 1.0 - (k * relStep) ) ) + floorPixel );  
   	    	if (maxPixel<floorPixel)    tempThresh = round ( ( abs(maxPixel - floorPixel) * ( 1.0 - (k * relStep) ) ) + maxPixel );
			lowerLimits[k] = tempThresh;   
  		}
	}

	//if (calledFromAnotherMacro==false) print(" ");

// ===============================================================r====================================   
// ======== Part 4: run thresholds and add puncta that pass criteria to a cumulative image =============================================
//====================================================================================================================

run("Set Measurements...", "area mean standard min centroid center perimeter fit shape integrated display redirect=None decimal=3");
timeA = getTime();
checkPoint = 0;                                //check if at least 1 set of particles has been counted

ceiling = 65555;
if (floorPixel>maxPixel) ceiling = floorPixel;



for (i=0; i<lowerLimits.length; i++) {
	print("\\Update2:ROI counting in lap " + (i+1) + " of " + lowerLimits.length);
	print("\\Update3: est time remaining (s): " + (lowerLimits.length-i-1)*( (getTime() - timeA) / (1000 * (i+1) ) ) ) ;

	selectWindow("working");
	resetThreshold();
	if (floorPixel<maxPixel) setThreshold(lowerLimits[i], ceiling);
	if (floorPixel>maxPixel) setThreshold(maxPixel,lowerLimits[i]);

	run("Analyze Particles...", "size=" + minParticle + "-" + maxParticle + " circularity=" + minCircularity + "-" + maxCircularity + " show=Masks display clear add");

	if ( (nResults!=0) || (checkPoint>1) ) {
		checkPoint = checkPoint +1;
			if (checkPoint == 1 ) {
				rename("previousPuncta");
			}
			if ( checkPoint > 1 ) {
				nextName = "puncta "+ lowerLimits[i];
				rename(nextName);
					if (noMerging == true) {
						selectWindow("previousPuncta");
						ultPts = "UltimatePoints";
						run("Duplicate...", "title="+ultPts);
						run("Ultimate Points");
						run("Clear Results");
						run("Multiply...", "value=255");
						run("Divide...", "value=255");
						roiManager("Measure");
						close();
						nROIk = roiManager("count");
						selectWindow(nextName);
						for (k=0; k<nROIk;k++) {
							if (getResult("IntDen", k)>1){					
								roiManager("Select",k);
								run("Fill");
							}
						}
						roiManager("Deselect");
						imageCalculator("OR create", "previousPuncta",nextName);
						rename("Or");
	
					} else {
						imageCalculator("OR create", "previousPuncta",nextName);
						rename("Or");

					}
				
				selectWindow(nextName);
					close();
				selectWindow("previousPuncta");
	 				close();
				selectWindow("Or");
				rename("previousPuncta");

				// 130612 (corrected 130712): experimental - running watershed at each loop to refine segmentation
				if (doWatershed == true) run("Watershed");
				if (drawContours == true) {
					run("Analyze Particles...", "size=0-Infinity circularity=0.00-1.00 show=[Masks] display exclude clear");
					//add to imgCountours
					run("Divide...", "value=255");
					run("16-bit");
					imageCalculator("ADD", imgContours,"Mask of previousPuncta");
					selectWindow("Mask of previousPuncta");
					close();
					selectWindow(imgContours);
					//wait(200);
					//run("Skeletonize");
					selectWindow("previousPuncta");
				}
			}
  	} // nResults!=0 loop
  	//waitForUser;
}       // end i loop

	// ==== 110815 v3.2- added option to run a watershed filter on the final binary image ====================
	if (doWatershedFinal == true) run("Watershed");

	if ( (roiManager("count")>=1) && ((nResults!=0) || (checkPoint>1)) ) {
	//	if (roiManager("count")>0) {
	               roundedFloor = round(floorPixel);
		intSD = floor(SD);
	 	if (stepMethod == "step size") definedStepSize = "yes";
	 	if (stepMethod != "step size") definedStepSize = "no";
		
		// ====== save analysis parameters in the puncta image header. Should always be able to reconstruct analysis from this info. ===================
		setMetadata("Info", "# SDs: " + xStandardDeviations + "\n # thresholds: " + nThresholds + "\n user defined: " + stepMethod + "\n autothreshold used: " + autoThresholdMethod + "\n applied watershed to  image: " + doWatershed + "\n background: " + roundedFloor  
		+  "\n SD: " + intSD + "\n stepSize: " + stepSize + "\n Max Intensity: " + maxPixel +"\n lowest threshold: " + lowerLimits[nThresholds-1] + "\n min puncta Size:" + minParticle 
		+ "\n max puncta Size: " + maxParticle + "\n min circularity: " + minCircularity + "\n max circularity: " + maxCircularity + "\n min Round: " + minSolidity + "\n max Round: " + maxSolidity
		+ "\n doWatershed:" + doWatershed + "\n borderWidth:" + borderWidth + "\n drawContours:" + drawContours + "\n noMerging" + noMerging
		+ "\n Multiple Thresholds version: " + version + "");
	
		i = i-1;

	
		//============ update output file names ============================================================================
		// add details to output names
		// 130518: v4.0 made threshold values optional in file names
		suffix = "multThrld";                          // 	
		if (labelWithThresholds == true) { 
		               thresholds =  "_" + lowerLimits[0] + "-" + lowerLimits[i]; // refers to variable coded into final name
		}
		// finalName = baseName + "_" + suffix;    // now defined earlier with some dummie place holders        // name of output image
		finalName = baseName + "_" + suffix + thresholds + z + c + "_v" + version;
        rename(finalName);
	
		// ============= save mask image ==================================================================================
		if (saveImages == true) {
			rename(finalName + ".tif");
			save(imagePath + finalName + ".tif");
		} else {
			rename(finalName + ".tif");
		}	
	
		// ============== show result of using a single threshold ====================================================================
		if (doSimpleThreshold == true) {                                // optional calculation of an equivalent simple threshold
      		selectWindow("working");
			resetThreshold();
			setThreshold(lowerLimits[i], ceiling);
			run("Analyze Particles...", "size=" + minParticle + "-" + maxParticle + " circularity=" +minCircularity + "-"+maxCircularity+" show=Masks display clear");
	            		simpleThName = baseName + "_sglThrld_" + lowerLimits[i];
			rename(simpleThName);
			if (saveImages == true) save(imagePath + simpleThName + ".tif");
	    }            
	
		// ================= generate list of ROIs ===============================================
		roiManager("reset");
		selectWindow(finalName + ".tif");
		//wait(500);
		setAutoThreshold();
		//run("Set Measurements...", "area mean min centroid center fit shape redirect=" + imageName + " decimal=3");
		run("Set Measurements...", "area mean standard min centroid center perimeter fit shape integrated display redirect=" + originalName + " decimal=3");
	
		// ==== 110815 v3.2- added option to run a watershed filter on the final binary image ====================
		if (doWatershed == true) run("Watershed");
		run("Analyze Particles...", "size=" + minParticle + "-Infinity circularity=" + minCircularity + "-"+maxCircularity+" display exclude clear add");
	
		//added 140408;
		run("Clear Results");
		roiManager("Measure");
	
		//====== compare all final ROIs and remove if their bounds hit the border ==============
		nROIs = roiManager("count");
		if (calledFromAnotherMacro==false) print("# ROIs found: "+ nROIs);

		tToClearBorder0 = getTime();
		// additional alternate: get last mask, duplicate with region exluding boarers, analyze particles excluding boarder, then translate all ROIs by border width)
		run("Set Measurements...", "area mean standard min centroid center perimeter fit shape integrated display redirect=None decimal=3");
		selectWindow(finalName + ".tif");	
		if (borderWidth>=0) {
			makeRectangle(borderWidth, borderWidth, w - 2*borderWidth, h - 2*borderWidth);
			doExclude = "exclude";
		}
		if (borderWidth<0) {
			makeRectangle(0, 0, w, h);
			doExclude = "";
		}
		
		imgRemoveBorder = "imgRemoveBorder";
		run("Duplicate...", "title="+imgRemoveBorder);
		roiManager("reset");
		selectWindow(imgRemoveBorder);	
		run("Analyze Particles...", "size=" + minParticle + "-Infinity circularity=" + minCircularity + "-" + maxCircularity + " " + doExclude + " clear add");
		roiManager("Deselect");
		roiManager("translate", borderWidth, borderWidth);
		selectWindow(imgRemoveBorder);	
		close();
		selectWindow(finalName + ".tif");	
		run("Select None");
		nROIsNotOnBorder = roiManager("count");
		
		print("\\Update4: ROIs passed border clearing: "+ nROIsNotOnBorder + " of " + nROIs);
		if (calledFromAnotherMacro==false) print("Time to clear border = " + (getTime() - tToClearBorder0)/60000 + " min");
		nROIs = nResults;

		//======= test if ROIs need to be removed due to having "Round" outside the specified limits ==========
		tToClearBorder1 = getTime();
		roisToDelete = newArray(nROIs);
		nToDelete = 0;
		if ((minSolidity != 0) || (maxSolidity!=1.0) ) {
			showStatus("filter by solidity limits");
			for (i = 1; i <= nROIs; i++) {
				//if (i % 10 == 0) showStatus("filter by round: " + floor(100*i/nROIs) + " %");
				j = nROIs - i;
				if (calledFromAnotherMacro==false)print(nROIs);
				if ( (getResult("Solidity", j) < minSolidity) || (getResult("Solidity", j) > maxSolidity)) {
					roisToDelete[nToDelete] = j;
					nToDelete = nToDelete  +1;
				}
			}
			roisToDelete = Array.trim(roisToDelete,nToDelete);
			checkDeleteTime = getTime();
			if (nToDelete > 0) {
				showStatus("removing ROIs outside round limits");
				roiManager("select",roisToDelete);
				roiManager("Delete");
			}

		}
		run("Set Measurements...", "area mean standard min centroid center perimeter fit shape integrated display redirect=" + originalName + " decimal=3");
		run("Clear Results");
		roiManager("Measure");
		print("\\Update5: ROIs within Round limits: "+ roiManager("count") + " of " + nROIs);

	
		// ====== clean up mask images =========================================
		//for (q=0;q<nImages;q++) { 
		//	n = nImages - q;
		//	if (calledFromAnotherMacro==false) print("\\Update: Closed "+ q + " of " + nImages + " mask images");
		//	selectImage(n);
		//	if ( indexOf(getTitle(), "Mask of")!=-1) 	close();
		//}
	
		// ===== 121003 v3.9 - restore image to orginal state if background was subtracted ============
		if (ballSize != -1) {
			selectWindow(imageName);
			run("Revert");  
		}
		selectWindow(finalName + ".tif");
		close();
	    resetThreshold();
		close("workin*");

		tSave = getTime();
		if (calledFromAnotherMacro==false) print("saving ROIs to image directory");
		if (roiManager("count")>0) roiManager("Save",getDirectory("home")+"multipleThresholdsROIset.zip");
		if (calledFromAnotherMacro==false) print("time to save temp ROIs: " + (getTime()-tSave)/1000 + " s");
	
		if ((saveResults == true)&&(imageHasPath == true)) {
			if (calledFromAnotherMacro==false) print("saving measurements");
			if (roiManager("count")>0) saveAs("Measurements", "" + imagePath + finalName + "_measured_ROIs.txt");   // need to generate path name
			if (roiManager("count")>0) roiManager("deselect");
			tSave = getTime();
			if (calledFromAnotherMacro==false) print("copying temp ROIs to image directory");
			if (roiManager("count")>0) File.copy(getDirectory("home")+"multipleThresholdsROIset.zip", imagePath + finalName + "_ROIs.zip");
			if (calledFromAnotherMacro==false) print("time to copy ROIs: " + (getTime()-tSave)/1000 + " s");
	    }
	    if ((saveResults == true)&&(imageHasPath == false)) {
			if (calledFromAnotherMacro==false) print("saving measurements");
			if (roiManager("count")>0) saveAs("Measurements", "" + imagePath + finalName + "_measured_ROIs.txt");   // need to generate path name
			if (roiManager("count")>0) roiManager("deselect");
			tSave = getTime();
			if (calledFromAnotherMacro==false) print("copying temp ROIs to image directory");
			if (roiManager("count")>0) File.copy(getDirectory("home")+"multipleThresholdsROIset.zip", imagePath + finalName + "_ROIs.zip");
			if (calledFromAnotherMacro==false) print("time to copy ROIs: " + (getTime()-tSave)/1000 + " s");
	    	
	    }

		
		selectWindow(imageName);
		rename(originalName);
		selectWindow(originalName);
		for (i = nImages; i >= 1; i--) {
			selectImage(i);
			if (indexOf(getTitle(),"Mask of")!=-1) close();
		}
		

		if (calledFromAnotherMacro==false) setBatchMode("exit and display"); 
		retrieveTime = getTime();
		if (calledFromAnotherMacro==false) print("retrieving ROIs");
		if (File.exists(getDirectory("home")+"multipleThresholdsROIset.zip")) {
			roiManager("reset");
			roiManager("Open",getDirectory("home")+"multipleThresholdsROIset.zip");
			//note that File.delete returns a "1", if not assigned to a variable, this prints to the log
			//redirect1 = File.delete(getDirectory("home")+"multipleThresholdsROIset.zip"); 
			
			//print("\\Update:"); 
			roiManager("Show All without labels");
			//roiManager("Show All");
		} else {
			if (calledFromAnotherMacro==false) print("\\Update9: No ROIs found with the current settings");	
		}
		if (calledFromAnotherMacro==false)	print("Time to retrieve ROIs: " + (getTime()-retrieveTime)/1000 + " s" );

	
	} else {
		
		close("worki*");
		for (i = nImages; i >= 1; i--) {
			selectImage(i);
			if (indexOf(getTitle(),"Mask of")!=-1) close();
		}

		// added 121003 v3.9 - restore image to orginal state if background was subtracted
		if (ballSize != -1) {
			selectWindow(imageName);
			run("Revert");  
		}
		selectWindow(imageName);
		rename(originalName);
		selectWindow(originalName);
		if (calledFromAnotherMacro==false) setBatchMode("exit and dispaly");
		if (calledFromAnotherMacro == false) exit("no puncta could be found \n with these parameteres");

	}


	if (calledFromAnotherMacro == false) setBatchMode("exit and dispaly");
	run("Set Measurements...", "area mean standard min centroid center perimeter fit shape integrated display redirect=None decimal=3");
	if (calledFromAnotherMacro==false) print("\\Update3: total time elapsed: " + (getTime()-timeStart)/1000 + " s"); 



	//run("Set Measurements...", "area mean min centroid shape redirect=None decimal=3");

	//====================================================================================
	//=============== FUNCTIONS===========================================================
	//====================================================================================
	
	
	function getBaseName(name) {
		suffixArray = newArray(".tif", ".tiff", ".jpg", ".jpeg", ".lsm",".TIF",".ND2",".TIFF",".NEF",".bmp",".png");
	 	for (i=0;i<suffixArray.length;i++) {
			if( endsWith(name,suffixArray[i])==true) name = replace(name, suffixArray[i],"");
		}
		return name;
	}
	
	function getFileExtension(name) {
		fileExtension= "";
		fileExtensionArray = newArray(".tif", ".tiff", ".jpg", ".jpeg", ".lsm",".TIF",".ND2",".TIFF",".NEF",".bmp",".png");
	 	for (i=0;i<fileExtensionArray.length;i++) {
			if( endsWith(name,fileExtensionArray[i])==true) fileExtension = fileExtensionArray[i];
		}
		return fileExtension;
	}



} // close macro
