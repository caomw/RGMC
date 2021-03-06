    warning off
    outputVideoPath =  ('.\outputVideos\');
    mkdir(outputVideoPath)
    outputFilePath =  ('.\outputFiles\');
    mkdir(outputFilePath)    
    datapath =  ('C:\SampleVideos\');     
    fileName = 'input.mp4';
    
    % Canvas size, relative to the original video size
    posSpanX = 2; % Sum of absolute of posSpanX and negSpanX should not exceed 4
    negSpanX = -2;
    posSpanY = 1; % Sum of absolute of posSpanY and negSpanY should not exceed 2.26
    negSpanY = -1; %0:1 gives the original canvas
    
    resizeFactor = 1;
    startFrame = 1;
    endFrame = 60;    
    displayFlag = true;

    initialize;
    
    % RGMC parameters
    alpha = 0.5;            
    step = 1;               % Process only frames 1+i * step 
    T_E = 2;                % Max. error handling iterations
    T_C = 50;               % Max. cluster analysis iterations
    T_M = 100;              % Max. cluster merging iterations
    etta = 1.5;             % Error tolerance
    tforms = {};
    while (ii + step) < vidObj.NumberOfFrames-1 && ((ii + step) <= endFrame)
        disp('---------------------')
        tic
        disp(['Frame ', num2str(ii), ' being processed...'])

        prevTrans = mytform;

        ii = ii + step;
        totalFramesProcd = totalFramesProcd + 1;
        imgA = imgB; 
        imgB = double(read(vidObj, ii)) / 255;
        imgB = imresize(imgB, resizeFactor);

        iterationCount = 0;
        objArr(ii) = 10e6;
        bestECC = 10e6;
        if (totalFramesProcd > 2)
            while  ((bestECC >= etta  *  mean(objArr(ii - 2 : ii - 1))) & (iterationCount < T_E))
                bestECCOld = bestECC;
                [newtform, newdiffImg, bestECC] = findTform(rgb2gray(imgA), rgb2gray(imgB), M, prevTrans, displayFlag, T_C, T_M);
                iterationCount = iterationCount + 1;
                if (bestECC < objArr(ii))
                    objArr(ii) = bestECC;
                    mytform = newtform;
                    diffImg = newdiffImg;
                end
                if (iterationCount > 1)
                    disp(['Error Handling_',num2str(iterationCount),':',num2str(bestECC),' (was:',num2str(bestECCOld),', goal:', num2str(2 * mean(objArr(ii-min(5,length(objArr)-2):step:ii-1))),')'])
                end
            end
            if (objArr(ii) > etta  *  mean(objArr(ii - 2 : ii - 1)))        
                diffImg = zeros(size(newdiffImg));
                disp('Not recovered')
            end        
        else
            [newtform, newdiffImg, bestECC] = findTform(rgb2gray(imgA), rgb2gray(imgB), M, prevTrans, displayFlag, T_C, T_M);
            objArr(ii) = bestECC;
            mytform = newtform;
            diffImg = newdiffImg;        
        end

        % Update motion history
        M = alpha  *  M + (1 - alpha)  *  (abs(diffImg)); 

        H = mytform.T;       
        tforms{ii} = H;   
        Hcumulative = H  *  Hcumulative;

        % Obtain frame difference image
        imgBpLocal = imwarp(imgB, projective2d(H), 'OutputView', imref2d(size(imgA)));
        diffImg = abs(rgb2gray(imgA)-rgb2gray(imgBpLocal));

        % Map current frame to the global motion-compensated coordinates
        imgBp = imwarp(imgB, projective2d(Hcumulative), 'OutputView', tempref);

        % Update "only" those pixels in the overlaied image which correspond to
        % the transformed pixels from current frame
        borderP = imwarp(ones(size(imgB)), projective2d(Hcumulative), 'OutputView', tempref);     
        temp = borderP > 0;
        erodedTemp = imerode(temp, se);
        overlaidIm(erodedTemp) = imgBp(erodedTemp);
        % overlaidIm(erodedTemp == 1) = (totalFramesProcd - 1)  /  totalFramesProcd  *  overlaidIm(erodedTemp == 1) + 1  /  totalFramesProcd  *  imgBp(erodedTemp == 1);
        figure(55);imshow(overlaidIm);drawnow;title('Overlaid frames')    
        toc
    end

    save(['.\outputFiles\',fileName,'_tforms.mat'], 'tforms','objArr');
           
%% Find the required canvas size 
[minX, minY, maxX, maxY] = findCanvasSize(tforms, size(imgB));
%%
tempref = imref2d(double(([(abs(maxY-minY)+1),(abs(maxX-minX)+1)])));
tempref.XWorldLimits = [minX maxX];
tempref.YWorldLimits = [minY maxY];   

%% Writing output video            
overlaid = uint8(zeros(abs(maxY-minY)+1, abs(maxX-minX)+1,3));

se = strel('disk', 10);     
writerObj = VideoWriter([outputVideoPath,'\RGMCd_',fileName],'MPEG-4'); 
writerObj.FrameRate = vidObj.FrameRate;
open(writerObj)

clear Hcumulative;
Hcumulative = eye(3);

endF = size(tforms,2);
for j = 2 : 1 : endF
    disp(['Writing frame ', num2str(j), ' ...'])
    if (~isempty(tforms{j}))
        imgB = read(vidObj,j);
        Hcumulative = tforms{j} * Hcumulative;
        imgB = imresize(imgB, resizeFactor);
        imgBp = imwarp(imgB, projective2d(Hcumulative), 'linear', 'OutputView', tempref); 
        % Update "only" those pixels in the overlaied image which correspond to
        % the transformed pixels from current frame        
        borderP = imwarp(ones(size(imgB)), projective2d(Hcumulative), 'linear','OutputView', tempref);
        temp = borderP > 0;                    
        erodedTemp = imerode(temp,se);
        overlaid(erodedTemp) = imgBp(erodedTemp);

        figure(2222);
        imshow(overlaid);axis equal; axis tight;axis off;
        title('Final result')
        drawnow
 
        scaleX = 1086 / size(overlaid, 1);
        scaleY = 1918 / size(overlaid, 2);
        scale = min([1, scaleX, scaleY]);
        if (scale ~= 1)
            overlaidResized = imresize(overlaid, scale);
        else
            overlaidResized = overlaid;
        end
        writeVideo(writerObj,overlaidResized);
    end
end   
close(writerObj)


