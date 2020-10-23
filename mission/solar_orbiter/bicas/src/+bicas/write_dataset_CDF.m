%
% Function that writes one dataset CDF file.
%
%
% BUG: write_nominal_dataset_CDF seems to only be able to overwrite pre-existing
% (proper) CDF files, but not empty pre-existing files.
%
%
% ARGUMENTS
% =========
% ZvsSubset : Struct with those zVars which should be written to
%             CDF. "Subset" since it excludes those zVars in the master file,
%             and which should NOT be overwritten.
% GaSubset  : Struct with fields representing a subset of the CDF
%             global attributes. A specific set of fields is required.
% 
%
% Author: Erik P G Johansson, Uppsala, Sweden
% First created 2020-06-24 as a separate file, by moving out the function from
% bicas.executed_sw_mode.
%
function write_dataset_CDF(...
        ZvsSubset, GaSubset, outputFile, masterCdfPath, SETTINGS, L)
    
    % PROPOSAL: Use setting PROCESSING.ZV_QUALITY_FLAG_MAX to cap zVar
    %   QUALITY_FLAG.
    %   PRO: Replaces other code in multiple locations.
    %   PRO/CON: Presumes that every output dataset has a zVar QUALITY_FLAG.
    
    %===========================================================================
    % This function needs GlobalAttributes values from the input files:
    %    One value per file:      Data_version (for setting Parent_version).
    %    Data_version ??!!
    %
    % PROPOSAL: Accept GlobalAttributes for all input datasets?!
    % PROBLEM: Too many arguments.
    % TODO-DEC: Should function find the master CDF file itself?
    %===========================================================================
    
    
    
    % UI ASSERTION: Check for directory collision. Always error.
    if exist(outputFile, 'dir')     % Checks for directory.
        error(...
            'BICAS:write_dataset_CDF', ...
            'Intended output dataset file path matches a pre-existing directory.')
    end
    % UI ASSERTION: Check for output file path collision with pre-existing file.
    if exist(outputFile, 'file')    % Command checks for file and directory (can not do just file).
        [settingValue, settingKey] = SETTINGS.get_fv('OUTPUT_CDF.PREEXISTING_OUTPUT_FILE_POLICY');
        
        anomalyDescrMsg = sprintf('Intended output dataset file path "%s" matches a pre-existing file.', outputFile);
        bicas.default_anomaly_handling(L, settingValue, settingKey, 'E+W+illegal', ...
            anomalyDescrMsg, 'BICAS:write_dataset_CDF')
    end
    
    
    
    
    %===========================
    % Create (modified) dataobj
    %===========================
    % NPEF = No Processing Empty File
    [settingNpefValue, settingNpefKey] = SETTINGS.get_fv('OUTPUT_CDF.NO_PROCESSING_EMPTY_FILE');
    if ~settingNpefValue
        
        %===================================================================
        % Set global max value for zVar QUALITY_FLAG
        % ------------------------------------------
        % NOTE: min(... 'includeNaN') implies that NaN always counts as the
        % lowest value.
        %===================================================================
        % PROPOSAL: Turn into generic function for capping QUALITY_FLAG based on
        % arbitrary setting.
        [value, key] = SETTINGS.get_fv('PROCESSING.ZV_QUALITY_FLAG_MAX');
        assert((0 < value) && (value <= 3), 'Illegal setting "%s"=%i.', key, value)
        if value < 3
            L.logf('warning', ...
                'Using setting %s = %i to set a zVar QUALITY_FLAG global max value.', ...
                key, value);
        end
        ZvsSubset.QUALITY_FLAG = min(...
            ZvsSubset.QUALITY_FLAG, ...
            value, 'includeNaN');
        
        
        DataObj = init_modif_dataobj(ZvsSubset, GaSubset, masterCdfPath, outputFile, SETTINGS, L);
        % NOTE: This call will fail if setting
        % OUTPUT_CDF.NO_PROCESSING_EMPTY_FILE=1 since processing is disabled and
        % therefore ZvsSubset=[] (can not be generated).
    end
    
    
    
    %===========================================
    % ASSERTIONS / Checks before writing to CDF
    %===========================================
    
    % Check if file writing is deliberately disabled.
    % NOTE: Do this as late as possible, in order to be able to test as much
    % code as possible without writing file.
    [settingValue, settingKey] = SETTINGS.get_fv('OUTPUT_CDF.WRITE_FILE_DISABLED');
    if settingValue
        L.logf('warning', 'Writing output CDF file is disabled via setting %s.', settingKey)
        return
    end
    
    if ~settingNpefValue
        write_nominal_dataset_CDF(DataObj, outputFile, SETTINGS, L)
    else
        L.logf('warning', 'Writing empty output file due to setting %s.', settingNpefKey)
        write_empty_file(outputFile)
    end

end



% Create a modified dataobj that can be written to file.
% (dataobj is based on master CDF.)
%
%
% NOTE: Assertions require that ZvsSubset contains records of data. Can not
% easily submit "no data" for debugging purposes (deactivate processing but
% still write file).
%
function DataObj = init_modif_dataobj(ZvsSubset, GlobalAttributesSubset, masterCdfPath, outputFile, SETTINGS, L)
    %============
    % ASSERTIONS
    %============
    if ~isfield(ZvsSubset, 'Epoch')
        error('BICAS:write_dataset_CDF', ...
            'Data for output dataset "%s" has no zVariable Epoch.', ...
            outputFile)
    end
    if isempty(ZvsSubset.Epoch)
        error('BICAS:write_dataset_CDF', ...
            'Data for output dataset "%s" contains an empty zVariable Epoch.', ...
            outputFile)
    end
    if ~issorted(ZvsSubset.Epoch, 'strictascend')
        error('BICAS:write_dataset_CDF', ...
            'Data for output dataset "%s" contains a zVariable Epoch that does not increase monotonically.', ...
            outputFile)
    end
    EJ_library.assert.struct(GlobalAttributesSubset, ...
        {'Parents', 'Parent_version', 'Provider', 'Datetime', 'OBS_ID', 'SOOP_TYPE'}, {})
    
    
    
    %======================
    % Read master CDF file
    %======================
    L.logf('info', 'Reading master CDF file: "%s"', masterCdfPath)
    DataObj = dataobj(masterCdfPath);
    ZvsLog  = struct();   % zVars for logging.
    
    %======================================================
    % Iterate over all OUTPUT PD field names (~zVariables)
    % - Set corresponding dataobj zVariables
    %======================================================
    % NOTE: Only sets a SUBSET of the zVariables in master CDF.
    pdFieldNameList = fieldnames(ZvsSubset);
    L.log('info', 'Converting PDV to dataobj (CDF data structure)')
    for iPdFieldName = 1:length(pdFieldNameList)
        zvName = pdFieldNameList{iPdFieldName};
        
        % ASSERTION: Master CDF already contains the zVariable.
        if ~isfield(DataObj.data, zvName)
            error('BICAS:write_dataset_CDF:Assertion:SWModeProcessing', ...
                'Trying to write to zVariable "%s" that does not exist in the master CDF file.', zvName)
        end
        
        zvValue = ZvsSubset.(zvName);
        ZvsLog.(zvName) = zvValue;
        
        %======================================================================
        % Prepare PDV zVariable value:
        % (1) Replace NaN-->fill value
        % (2) Convert to the right MATLAB class
        %
        % NOTE: If both fill values and pad values have been replaced with NaN
        % (when reading CDF), then the code can not distinguish between fill
        % values and pad values.
        %======================================================================
        if isfloat(zvValue)
            [fillValue, ~] = bicas.get_fill_pad_values(DataObj, zvName);
            zvValue        = EJ_library.utils.replace_value(zvValue, NaN, fillValue);
        end
        matlabClass = EJ_library.cdf.convert_CDF_type_to_MATLAB_class(...
            DataObj.data.(zvName).type, 'Permit MATLAB classes');
        zvValue     = cast(zvValue, matlabClass);
        
        % Set zVariable.
        DataObj.data.(zvName).data = zvValue;
    end
    
    
    
    % Log data to be written to CDF file.
    bicas.proc_utils.log_zVars(ZvsLog, SETTINGS, L)
    
    %==========================
    % Set CDF GlobalAttributes
    %==========================
    DataObj.GlobalAttributes.Software_name       = bicas.constants.SWD_METADATA('SWD.identification.name');
    DataObj.GlobalAttributes.Software_version    = bicas.constants.SWD_METADATA('SWD.release.version');
    % Static value?!!
    DataObj.GlobalAttributes.Calibration_version = SETTINGS.get_fv('OUTPUT_CDF.GLOBAL_ATTRIBUTES.Calibration_version');
    % BUG? Assigns local time, not UTC!!! ROC DFMD does not mention time zone.
    DataObj.GlobalAttributes.Generation_date     = datestr(now, 'yyyy-mm-ddTHH:MM:SS');         
    DataObj.GlobalAttributes.Logical_file_id     = get_logical_file_id(outputFile);
    DataObj.GlobalAttributes.Parents             = GlobalAttributesSubset.Parents;
    DataObj.GlobalAttributes.Parent_version      = GlobalAttributesSubset.Parent_version;
    DataObj.GlobalAttributes.Provider            = GlobalAttributesSubset.Provider;
    DataObj.GlobalAttributes.Datetime            = GlobalAttributesSubset.Datetime;
    DataObj.GlobalAttributes.OBS_ID              = GlobalAttributesSubset.OBS_ID;
    DataObj.GlobalAttributes.SOOP_TYPE           = GlobalAttributesSubset.SOOP_TYPE;
    %DataObj.GlobalAttributes.SPECTRAL_RANGE_MIN
    %DataObj.GlobalAttributes.SPECTRAL_RANGE_MAX
    
    % "Metadata Definition for Solar Orbiter Science Data", SOL-SGS-TN-0009:
    %   "TIME_MIN   The date and time of the beginning of the first acquisition
    %               for the data contained in the file"
    %   "TIME_MAX   The date and time of the end of the last acquisition for the
    %               data contained in the file"
    %   States that TIME_MIN, TIME_MAX should be "Julian day" (not "modified
    %   Julian day", which e.g. OVT uses internally).
    % NOTE: Implementation does not consider the integration time of each
    % sample.
    % NOTE: juliandate() is consistent with Julian date converter at
    % https://www.onlineconversion.com/julian_date.htm
    DataObj.GlobalAttributes.TIME_MIN = juliandate(EJ_library.cdf.TT2000_to_datevec(ZvsSubset.Epoch(1  )));
    DataObj.GlobalAttributes.TIME_MAX = juliandate(EJ_library.cdf.TT2000_to_datevec(ZvsSubset.Epoch(end)));
    
    % ROC DFMD hints that value should not be set dynamically. (See meaning of
    % non-italic black text for global attribute name in table.)
    %DataObj.GlobalAttribute.CAVEATS = ?!!
    
    
    
    %==============================================
    % Handle still-empty zVariables (zero records)
    %==============================================
    for fn = fieldnames(DataObj.data)'
        zvName = fn{1};
        
        if isempty(DataObj.data.(zvName).data)
            %==============================================================
            % CASE: zVariable has zero records.
            % This indicates that it should have been set using PDV field.
            %==============================================================
            
            % NOTE: Useful to specify master CDF path in the case of having
            % multiple output datasets. Will otherwise not know which output
            % dataset is referred to. Note: Can still read master CDF from
            % preceeding log messages.
            anomalyDescrMsg = sprintf(...
                ['Master CDF "%s" contains zVariable "%s" which has not been', ...
                ' set (i.e. it has zero records) after adding ', ...
                'processing data. This should only happen for incomplete processing.'], ...
                masterCdfPath, zvName);
            
            matlabClass   = EJ_library.cdf.convert_CDF_type_to_MATLAB_class(...
                DataObj.data.(zvName).type, 'Permit MATLAB classes');
            isNumericZVar = isnumeric(cast(0.000, matlabClass));
            
            if isNumericZVar
                %====================
                % CASE: Numeric zVar
                %====================
                [settingValue, settingKey] = SETTINGS.get_fv('OUTPUT_CDF.EMPTY_NUMERIC_ZV_POLICY');
                switch(settingValue)
                    case 'USE_FILLVAL'
                        %========================================================
                        % Create correctly-sized zVariable data with fill values
                        %========================================================
                        % NOTE: Assumes that
                        % (1) there is a PD fields/zVariable Epoch, and
                        % (2) this zVariable should have as many records as Epoch.
                        L.logf('warning', ...
                            ['Setting numeric master/output CDF zVariable "%s" to presumed correct size using fill', ...
                            ' values due to setting "%s" = "%s".'], ...
                            zvName, settingKey, settingValue)
                        
                        nEpochRecords  = size(ZvsSubset.Epoch, 1);
                        [fillValue, ~] = bicas.get_fill_pad_values(DataObj, zvName);
                        zvSize  = [nEpochRecords, DataObj.data.(fn{1}).dim];
                        zvValue = cast(zeros(zvSize), matlabClass);
                        zvValue = EJ_library.utils.replace_value(zvValue, 0, fillValue);
                        
                        DataObj.data.(zvName).data = zvValue;
                        
                    otherwise
                        bicas.default_anomaly_handling(L, settingValue, settingKey, 'E+W+illegal', anomalyDescrMsg, ...
                            'BICAS:write_dataset_CDF:SWModeProcessing:DatasetFormat')
                end
                
            else
                %========================
                % CASE: Non-numeric zVar
                %========================
                [settingValue, settingKey] = SETTINGS.get_fv('OUTPUT_CDF.EMPTY_NONNUMERIC_ZV_POLICY');
                bicas.default_anomaly_handling(L, settingValue, settingKey, 'E+W+illegal', anomalyDescrMsg, ...
                    'BICAS:write_dataset_CDF:SWModeProcessing:DatasetFormat')
            end
        end
    end
    
end    % init_modif_dataobj



% NOTE: Unclear if can overwrite CDFs. Varies depending on file.
%
function write_nominal_dataset_CDF(DataObj, outputFile, SETTINGS, L)
    %===========================================
    % Write to CDF file using write_CDF_dataobj
    %===========================================
    
    [strictNumericZvSizePerRecord, settingKey] = SETTINGS.get_fv('OUTPUT_CDF.write_dataobj.strictNumericZvSizePerRecord');
    if strictNumericZvSizePerRecord
        L.logf('warning', [...
            '========================================================================================================\n', ...
            'Permitting master CDF zVariable size per record to differ from the output CDF zVariable size per record.\n', ...
            'This is due to setting %s = "%g"\n', ...
            '========================================================================================================\n'], ...
            settingKey, strictNumericZvSizePerRecord);
    end
    
    L.logf('info', 'Writing dataset CDF file: %s', outputFile)
    EJ_library.cdf.write_dataobj( ...
        outputFile, ...
        DataObj.GlobalAttributes, ...
        DataObj.data, ...
        DataObj.VariableAttributes, ...
        DataObj.Variables, ...
        'calculateMd5Checksum',              true, ...
        'strictEmptyZvClass',                SETTINGS.get_fv('OUTPUT_CDF.write_dataobj.strictEmptyZvClass'), ...
        'strictEmptyNumericZvSizePerRecord', SETTINGS.get_fv('OUTPUT_CDF.write_dataobj.strictEmptyNumericZvSizePerRecord'), ...
        'strictNumericZvSizePerRecord',      strictNumericZvSizePerRecord)
end



function logicalFileId = get_logical_file_id(filePath)
    % Use the filename without suffix.
    [~, basename, ~] = fileparts(filePath);
    logicalFileId = basename;
end



% NOTE: Should always overwrite file.
function write_empty_file(filePath)
    fileId = fopen(filePath, 'w');    
    
    % ~ASSERTION
    if fileId == -1
        % NOTE: Technically non-BICAS error ID.
        error('BICAS:write_dataset_CDF:CanNotOpenFile', 'Can not open file: "%s"', filePath)
    end
    
    % NOTE: Does not have to write any data to create empty file.
    fclose(fileId);
end
