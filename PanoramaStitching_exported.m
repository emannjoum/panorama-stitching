classdef PanoramaStitchingFinal_exported < matlab.apps.AppBase

    % Properties that correspond to app components
    properties (Access = public)
        UIFigure                       matlab.ui.Figure
        AddImageButton                 matlab.ui.control.Button
        RemoveImageButton              matlab.ui.control.Button
        PanoramaImageStitcherLabel     matlab.ui.control.Label
        ThumbnailPanel                 matlab.ui.container.Panel
        UseSimilarityOrderingCheckBox  matlab.ui.control.CheckBox
        StitchButton                   matlab.ui.control.Button
        LoadImagesButton               matlab.ui.control.Button
        UIAxes2                        matlab.ui.control.UIAxes
        UIAxes                         matlab.ui.control.UIAxes
    end

    
    properties (Access = private)
        ImagesOriginal cell = {}
        stitchedImage
        ThumbnailAxes
        SelectedIndex double = 0            % Index of the selected image
        ThumbnailImages = [];
    end
    

    methods (Access = private)

        function resultImage = image_stitching(app, imagesOriginal)
        
            numImages = length(imagesOriginal);
            
            if numImages == 1
                resultImage = imagesOriginal{1};
                return;
            end
            
            mid = ceil(numImages/2);
            resultImage = imagesOriginal{mid};
            imagesOriginal(mid) = [];
            
            
            for i = 1:length(imagesOriginal)
            
                I1 = resultImage;
                I2 = imagesOriginal{i};
            
                gray1 = rgb2gray(I1);
                gray2 = rgb2gray(I2);

                points1 = detectSURFFeatures(gray1); % Detect & extract once
                points2 = detectSURFFeatures(gray2);
            
                [features1, validPoints1] = extractFeatures(gray1, points1);
                [features2, validPoints2] = extractFeatures(gray2, points2);
            
                indexPairs = matchFeatures(features1, features2, ...
                    'Unique', true, ...
                    'MaxRatio', 0.7, ...
                    'MatchThreshold', 50);
            
                if size(indexPairs,1) < 4
                    uialert(app.UIFigure, ...
                        'Not enough matching points between images.', ...
                        'Stitching Failed');
                    return;
                end
            
                matchedPoints1 = validPoints1(indexPairs(:,1));
                matchedPoints2 = validPoints2(indexPairs(:,2));
            
                tform = estimateGeometricTransform2D( ...
                    matchedPoints2, matchedPoints1, ...
                    'projective', ...
                    'Confidence', 99.9, ...
                    'MaxNumTrials', 2000);
            
                % limits of warped image
                [xlim, ylim] = outputLimits(tform, ...
                    [1 size(I2,2)], ...
                    [1 size(I2,1)]);
            
                xMin = floor(min([1; xlim(:)]));
                xMax = ceil(max([size(I1,2); xlim(:)]));
                yMin = floor(min([1; ylim(:)]));
                yMax = ceil(max([size(I1,1); ylim(:)]));
            
                width  = xMax - xMin;
                height = yMax - yMin;
            
                panoramaRef = imref2d([height width], [xMin xMax], [yMin yMax]);% Create reference frame
            
                % Warp both images into same reference
                warpedI2 = imwarp(I2, tform, 'OutputView', panoramaRef);
                warpedI1 = imwarp(I1, affine2d(eye(3)), 'OutputView', panoramaRef);
         
                mask1 = warpedI1 > 0; % Feather blending
                mask2 = warpedI2 > 0;
            
                overlap = mask1 & mask2;
            
                resultImage = warpedI1;
                resultImage(mask2 & ~overlap) = warpedI2(mask2 & ~overlap);
            
                % Smooth blend in overlap
                alpha = 0.5;
                resultImage(overlap) = uint8( ...
                    alpha * double(warpedI1(overlap)) + ...
                    (1 - alpha) * double(warpedI2(overlap)) );
            
            end
            
        end  
        
    function order = estimateImageOrder(app, images)
    
        numImages = length(images);
        
        features = cell(1, numImages);
        validPoints = cell(1, numImages);
        
        % Precompute features 
        for i = 1:numImages
            gray = rgb2gray(images{i});
            points = detectSURFFeatures(gray);
            [features{i}, validPoints{i}] = extractFeatures(gray, points);
        end
        
        scores = zeros(numImages);
        
        for i = 1:numImages
            for j = i+1:numImages
                indexPairs = matchFeatures(features{i}, features{j}, 'Unique', true);
                scores(i,j) = size(indexPairs,1);
                scores(j,i) = scores(i,j);
            end
        end
        
        % Start from most connected image
        totalMatches = sum(scores,2);
        [~, startIdx] = max(totalMatches);
        
        order = startIdx;
        visited = false(1,numImages);
        visited(startIdx) = true;
        
        for k = 2:numImages
            last = order(end);
            
            row = scores(last,:);
            row(visited) = -inf;
            
            [~, next] = max(row);
            
            order(end+1) = next;
            visited(next) = true;
        end
        
    end
 
        function selectThumbnail(app, index, imageObj)
        
            app.SelectedIndex = index;
        
            for i = 1:length(app.ThumbnailImages)
                app.ThumbnailImages(i).BorderWidth = 0;
            end
   
            imageObj.BorderWidth = 3;
            imageObj.BorderColor = 'red';
        
        end

        
        function updateMontage(app)
           
            if isempty(app.ImagesOriginal)
                cla(app.UIAxes);
            else
                montage(app.ImagesOriginal, 'Parent', app.UIAxes);
            end
            
        end

        
        function updateThumbnails(app)
            delete(findall(app.ThumbnailPanel, 'Type', 'uiimage'));
            delete(findall(app.ThumbnailPanel, 'Type', 'rectangle'));
        
            numImages = length(app.ImagesOriginal);
            app.ThumbnailImages = gobjects(1, numImages);
      
               
            for i = 1:numImages
                thumb = uiimage(app.ThumbnailPanel);
                thumb.ImageSource = app.ImagesOriginal{i};
                thumb.Position = [10 + mod(i-1, 4)*90, 250 - floor((i-1)/4)*90, 80, 80];
                thumb.ImageClickedFcn = @(src, event) selectThumbnail(app, i, src);
                app.ThumbnailImages(i) = thumb;
            end
            
        end
       

        
      end
                  

    % Callbacks that handle component events
    methods (Access = private)

        % Button pushed function: LoadImagesButton
        function LoadImagesButtonPushed(app, event)
             [filenames, pathname] = uigetfile( ...
                {'*.jpg;*.jpeg;*.png;*.bmp;*.tif;*.tiff;*.gif', 'All Image Files'; '*.*', 'All Files'}, ...
                'Select Images', 'MultiSelect', 'on');
        
            if isequal(filenames, 0)
                return;
            end
        
            if ischar(filenames)
                filenames = {filenames}; % Wrap in cell if only one file
            end
        
            app.ImagesOriginal = cell(1, numel(filenames));
            delete(findall(app.ThumbnailPanel, 'Type', 'uiimage'));
            delete(findall(app.ThumbnailPanel, 'Type', 'rectangle'));
            app.ThumbnailImages = gobjects(1, length(filenames));
            app.SelectedIndex = 0;
        
            for i = 1:numel(filenames)
                fullPath = fullfile(pathname, filenames{i});
                img = imread(fullPath);
                
                if ~isa(img, 'uint8')
                    img = im2uint8(img); % Normalization
                end

                if ndims(img) == 2 || (ndims(img) == 3 && size(img, 3) == 1)
                    img = cat(3, img, img, img);  % Convert grayscale to RGB
                end

                % Resize if needed
                scale = max(size(img, 1), size(img, 2));
                if scale > 400
                    img = imresize(img, 400 / scale);
                end
        
                app.ImagesOriginal{i} = img;
            end

            updateMontage(app);
            updateThumbnails(app);
        end

        % Button pushed function: StitchButton
        function StitchButtonPushed(app, event)
            if isempty(app.ImagesOriginal)
                uialert(app.UIFigure, 'Please load images first.', 'No Images Loaded');
                return;
            end
            
            app.UIFigure.Pointer = 'watch';
            cla(app.UIAxes2);  % Clear the stitched image axes
            drawnow;

            if app.UseSimilarityOrderingCheckBox.Value == 1
                order = app.estimateImageOrder(app.ImagesOriginal);
                orderedImages = app.ImagesOriginal(order);
                app.stitchedImage = app.image_stitching(orderedImages);
               imshow(app.stitchedImage, 'Parent', app.UIAxes2);
            else
        
           try
                app.stitchedImage = app.image_stitching(app.ImagesOriginal);
                imshow(app.stitchedImage, 'Parent', app.UIAxes2);
            catch ME
                uialert(app.UIFigure, ME.message, 'Stitching Failed');
           end
            end
                      
           app.UIFigure.Pointer = 'arrow'; % stop loading
           drawnow;
        end

        % Button pushed function: RemoveImageButton
        function RemoveImageButtonPushed(app, event)
           idx = app.SelectedIndex;

            if idx < 1 || idx > length(app.ImagesOriginal)
                uialert(app.UIFigure, 'Please select an image to remove.', 'No Selection');
                return;
            end
        
            app.ImagesOriginal(idx) = [];
            app.ThumbnailImages(idx) = [];
        
            app.SelectedIndex = 0;
            delete(findall(app.ThumbnailPanel, 'Tag', 'BorderRect')); % Reset selection and clear border
        
            updateThumbnails(app);
            updateMontage(app);
        end

        % Button pushed function: AddImageButton
        function AddImageButtonPushed(app, event)
        
            [filename, pathname] = uigetfile( ...
                {'*.jpg;*.jpeg;*.png;*.bmp;*.tif;*.tiff;*.gif', 'All Image Files'; '*.*', 'All Files'}, ...
                'Select an Image to Add');
        
            if isequal(filename, 0)
                return;
            end
        
            img = imread(fullfile(pathname, filename));
        
            if ~isa(img, 'uint8')
                img = im2uint8(img);
            end

            if ndims(img) == 2 || (ndims(img) == 3 && size(img,3) == 1)
                img = cat(3, img, img, img);
            end
        
            scale = max(size(img, 1), size(img, 2));
            if scale > 400
                img = imresize(img, 400 / scale);
            end

            app.ImagesOriginal{end + 1} = img;

            updateMontage(app);
            updateThumbnails(app);

        end
    end

    % Component initialization
    methods (Access = private)

        % Create UIFigure and components
        function createComponents(app)

            % Create UIFigure and hide until all components are created
            app.UIFigure = uifigure('Visible', 'off');
            app.UIFigure.Color = [1 1 1];
            app.UIFigure.Position = [100 100 817 503];
            app.UIFigure.Name = 'MATLAB App';

            % Create UIAxes
            app.UIAxes = uiaxes(app.UIFigure);
            app.UIAxes.XTick = [];
            app.UIAxes.YTick = [];
            app.UIAxes.LineWidth = 0.1;
            app.UIAxes.Box = 'on';
            app.UIAxes.Position = [32 219 357 235];

            % Create UIAxes2
            app.UIAxes2 = uiaxes(app.UIFigure);
            app.UIAxes2.XTick = [];
            app.UIAxes2.YTick = [];
            app.UIAxes2.LineWidth = 0.1;
            app.UIAxes2.Box = 'on';
            app.UIAxes2.Position = [402 219 359 234];

            % Create LoadImagesButton
            app.LoadImagesButton = uibutton(app.UIFigure, 'push');
            app.LoadImagesButton.ButtonPushedFcn = createCallbackFcn(app, @LoadImagesButtonPushed, true);
            app.LoadImagesButton.FontWeight = 'bold';
            app.LoadImagesButton.Position = [142 195 122 24];
            app.LoadImagesButton.Text = 'Load Images';

            % Create StitchButton
            app.StitchButton = uibutton(app.UIFigure, 'push');
            app.StitchButton.ButtonPushedFcn = createCallbackFcn(app, @StitchButtonPushed, true);
            app.StitchButton.FontWeight = 'bold';
            app.StitchButton.Position = [614 195 122 24];
            app.StitchButton.Text = 'Stitch';

            % Create UseSimilarityOrderingCheckBox
            app.UseSimilarityOrderingCheckBox = uicheckbox(app.UIFigure);
            app.UseSimilarityOrderingCheckBox.Text = 'Use Similarity Ordering';
            app.UseSimilarityOrderingCheckBox.Position = [448 197 145 22];

            % Create ThumbnailPanel
            app.ThumbnailPanel = uipanel(app.UIFigure);
            app.ThumbnailPanel.Title = 'ThumbnailPanel';
            app.ThumbnailPanel.FontWeight = 'bold';
            app.ThumbnailPanel.Scrollable = 'on';
            app.ThumbnailPanel.Position = [189 46 466 138];

            % Create PanoramaImageStitcherLabel
            app.PanoramaImageStitcherLabel = uilabel(app.UIFigure);
            app.PanoramaImageStitcherLabel.HorizontalAlignment = 'center';
            app.PanoramaImageStitcherLabel.FontName = 'Baskerville Old Face';
            app.PanoramaImageStitcherLabel.FontSize = 26;
            app.PanoramaImageStitcherLabel.FontWeight = 'bold';
            app.PanoramaImageStitcherLabel.Position = [264 461 296 35];
            app.PanoramaImageStitcherLabel.Text = 'Panorama Image Stitcher';

            % Create RemoveImageButton
            app.RemoveImageButton = uibutton(app.UIFigure, 'push');
            app.RemoveImageButton.ButtonPushedFcn = createCallbackFcn(app, @RemoveImageButtonPushed, true);
            app.RemoveImageButton.VerticalAlignment = 'top';
            app.RemoveImageButton.FontWeight = 'bold';
            app.RemoveImageButton.FontColor = [0.6353 0.0784 0.1843];
            app.RemoveImageButton.Position = [304 14 86 21];
            app.RemoveImageButton.Text = 'Remove';

            % Create AddImageButton
            app.AddImageButton = uibutton(app.UIFigure, 'push');
            app.AddImageButton.ButtonPushedFcn = createCallbackFcn(app, @AddImageButtonPushed, true);
            app.AddImageButton.FontWeight = 'bold';
            app.AddImageButton.FontColor = [0 0.4471 0.7412];
            app.AddImageButton.Position = [418 13 100 22];
            app.AddImageButton.Text = 'Add Image';

            % Show the figure after all components are created
            app.UIFigure.Visible = 'on';
        end
    end

    % App creation and deletion
    methods (Access = public)

        % Construct app
        function app = PanoramaStitchingFinal_exported

            % Create UIFigure and components
            createComponents(app)

            % Register the app with App Designer
            registerApp(app, app.UIFigure)

            if nargout == 0
                clear app
            end
        end

        % Code that executes before app deletion
        function delete(app)

            % Delete UIFigure when app is deleted
            delete(app.UIFigure)
        end
    end
end