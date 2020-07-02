%
% Class that collects functions related to finding/selecting and reading RCTs.
%
%
% DESIGN INTENT
% =============
% Implemented so that no calibration data is modified/added to/removed from. The returned data structures reflect the
% content of the RCTs, not necessarily the data used. Modification of data (in particular extrapolation of transfer
% functions) should be done elsewhere.
% --
% NOTE: Not entirely true. Code inverts LFR & BIAS RCT FTF-->ITF.
%
%
% Author: Erik P G Johansson, IRF-U, Uppsala, Sweden
% First created 2019-11-15
%
classdef RCT
% BOGIQ
% =====
% PROPOSAL: Use same code/function for reading calibration table, as for reading dataset (and master cdfs)?
% PROPOSAL: Assert CDF skeleton/master version number.
% PROPOSAL: Assert skeleton/master.
% PROPOSAL: Assert/warn (depending on setting?) file units in CDF metadata.
% PROPOSAL: Use utility function for reading every zVariable.
%   PROPOSAL: Assert units from zVar attributes.
%
% PROPOSAL: Move out the extrapolation of LFR TFs.
%   PRO: Want to distinguish between RCT data and modified data.
% PROPOSAL: Log read RCTs in the same way as input datasets; generic zVar logging.
%
% PROPOSAL: Read FTFs and have the caller (bicas.calib) invert the FTFs.



    properties(Access=private, Constant)
        
        % Minimum number of numerator or denominator coefficients in the BIAS RCT.
        N_MIN_TF_NUMER_DENOM_COEFFS = 8;
        
        % Minimum number of entries in tabulated transfer functions in RCTs.
        TF_TABLE_MIN_LENGTH = 10;
        
    end


    
    methods(Static, Access=public)
        
        
        
        % Determine the path to the RCT that should be used, using the filenaming convention specified in the
        % documentation (defined in SETTINGS), and according to algorithm specified in the documentation.
        %
        % Effectively a wrapper around bicas.RCT.find_RCT_regexp.
        %
        %
        % ARGUMENTS
        % =========
        % rctId : String constants representing RCT to be read.
        %
        function RctCalibData = find_RCT_by_SETTINGS_regexp(calibrationDir, rctId, SETTINGS, L)

            %============================
            % Create regexp for filename
            %============================
            % IMPLEMENTATION NOTE: Below translation statement
            % (1) verifies the argument, AND
            % (2) separates the argument string constants from the SETTINGS naming convention.
            analyzerSettingsSegm = EJ_library.utils.translate({...
                {'BIAS'},     'BIAS'; ...
                {'LFR'},      'LFR'; ...
                {'TDS-CWF'},  'TDS-LFM-CWF'; ...
                {'TDS-RSWF'}, 'TDS-LFM-RSWF'}, ...
                rctId, 'BICAS:calib:Assertion:IllegalArgument', sprintf('Illegal rctId="%s"', rctId));
            filenameRegexp = SETTINGS.get_fv(sprintf('PROCESSING.RCT_REGEXP.%s', analyzerSettingsSegm));
            
            RctCalibData = bicas.RCT.find_RCT_regexp(calibrationDir, filenameRegexp, L);
        end



        % Determine the path to the RCT that should be used according to algorithm specified in the documentation(?). If
        % there are multiple matching candidates, choose the latest one as indicated by the filename.
        %
        %
        % IMPLEMENTATION NOTES
        % ====================
        % Useful to have this as separate functionality so that the chosen RCT to use can be explicitly overridden via
        % e.g. settings.
        %
        function path = find_RCT_regexp(calibrationDir, filenameRegexp, L)

            %=================================================
            % Find candidate files and select the correct one
            %=================================================
            dirObjectList = dir(calibrationDir);
            dirObjectList([dirObjectList.isdir]) = [];    % Eliminate directories.
            filenameList = {dirObjectList.name};
            filenameList(~EJ_library.str.regexpf(filenameList, filenameRegexp)) = [];    % Eliminate non-matching filenames.
            
            % ASSERTION / WARNING
            if numel(filenameList) == 0
                % ERROR
                error('BICAS:calib:CannotFindRegexMatchingRCT', ...
                    'Can not find any calibration file that matches regular expression "%s" in directory "%s".', ...
                    filenameRegexp, calibrationDir);
            end
            % CASE: There is at least one candidate file.
            
            filenameList = sort(filenameList);
            filename     = filenameList{end};
            path         = fullfile(calibrationDir, filename);
            
            if numel(filenameList) > 1
                % WARNING/INFO/NOTICE
                msg = sprintf(...
                    ['Found multiple calibration files matching regular expression "%s"\n', ...
                     'in directory "%s".\n', ...
                     'Selecting the latest one as indicated by the filename: "%s".\n'], ...
                    filenameRegexp, calibrationDir, filename);
                for i = 1:numel(filenameList)
                    msg = [msg, sprintf('    %s\n', filenameList{i})];
                end
                L.log('debug', msg)
            end
            
            % IMPLEMENTATION NOTE: Not logging which calibration file is selected, since this function is not supposed
            % to actually load the content.
        end



        function [Bias] = read_BIAS_RCT(filePath)
            % TODO-DECISION: How handle time?
            %   PROPOSAL: "Only" access the BIAS values (trans.func and other) through a function instead of selecting indices in a data struct.
            %       PROPOSAL: (private method) [omegaRps, zVpc] = get_transfer_func(epoch, signalType)
            %           signalType = 'DC single' etc
            
            Do = dataobj(filePath);
            
            % Constants for interpreting the array indices in the CDF.
            NUMERATOR   = 1;
            DENOMINATOR = 2;
            %
            DC_SINGLE = 1;
            DC_DIFF   = 2;
            AC_LG     = 3;
            AC_HG     = 4;
            
            try
                % NOTE: Assumes 1 CDF record or many (time-dependent values).
                % ==> Must handle that dataobj assigns differently for these two cases.
                epochL                    = bicas.RCT.norm_do_zv(Do.data.Epoch_L);
                epochH                    = bicas.RCT.norm_do_zv(Do.data.Epoch_H);
                biasCurrentOffsetsAAmpere = bicas.RCT.norm_do_zv(Do.data.BIAS_CURRENT_OFFSET);      % DEPEND_0 = Epoch_L
                biasCurrentGainsAapt      = bicas.RCT.norm_do_zv(Do.data.BIAS_CURRENT_GAIN);        % DEPEND_0 = Epoch_L
                dcSingleOffsetsAVolt      = bicas.RCT.norm_do_zv(Do.data.V_OFFSET);                 % DEPEND_0 = Epoch_H
                dcDiffOffsetsAVolt        = bicas.RCT.norm_do_zv(Do.data.E_OFFSET);                 % DEPEND_0 = Epoch_H
                ftfCoeffs                 = bicas.RCT.norm_do_zv(Do.data.TRANSFER_FUNCTION_COEFFS); % DEPEND_0 = Epoch_L

                nEpochL = size(epochL, 1);
                nEpochH = size(epochH, 1);

                % IMPLEMENTATION NOTE: Corrects for what seems to be a bug in dataobj. dataobj permutes/removes indices,
                % and permutes them differently depending on the number of CDF records (but wrong in all cases).
                %
                % 1 CDF record : cdfdump: "TRANSFER_FUNCTION_COEFFS CDF_DOUBLE/1   3:[2,8,4]       F/TTT"   # 3=number of dimensions/record
                % 2 CDF records: cdfdump: "TRANSFER_FUNCTION_COEFFS CDF_DOUBLE/1   3:[2,8,4]       T/TTT"
                % 1 CDF record:   size(Do.data.TRANSFER_FUNCTION_COEFFS.data) == [  4 2 8]
                % 2 CDF records:  size(Do.data.TRANSFER_FUNCTION_COEFFS.data) == [2 4 2 8]                
                ftfCoeffs = permute(ftfCoeffs, [1, 4,3,2]);



                %=======================================================
                % ASSERTIONS: Size of tfCoeffs/TRANSFER_FUNCTION_COEFFS
                %=======================================================
                assert(size(ftfCoeffs, 1) == nEpochL)
                assert(size(ftfCoeffs, 2) >= bicas.RCT.N_MIN_TF_NUMER_DENOM_COEFFS)
                assert(size(ftfCoeffs, 3) == 2)
                assert(size(ftfCoeffs, 4) == 4)

                %================================
                % Assign struct that is returned
                %================================
                Bias.epochL = epochL;
                Bias.epochH = epochH;

                Bias.Current.offsetsAAmpere = biasCurrentOffsetsAAmpere;
                Bias.Current.gainsAapt      = biasCurrentGainsAapt;
                Bias.dcSingleOffsetsAVolt   = dcSingleOffsetsAVolt;
                Bias.DcDiffOffsets.E12AVolt = dcDiffOffsetsAVolt(:, 1);
                Bias.DcDiffOffsets.E13AVolt = dcDiffOffsetsAVolt(:, 2);
                Bias.DcDiffOffsets.E23AVolt = dcDiffOffsetsAVolt(:, 3);

                % NOTE: Using name "ItfSet" only to avoid "Itfs" (plural). (List, Table would be wrong? Use "ItfTable"?)
                Bias.ItfSet.DcSingleAvpiv = bicas.RCT.create_ITF_sequence(...
                    ftfCoeffs(:, :, NUMERATOR,   DC_SINGLE), ...
                    ftfCoeffs(:, :, DENOMINATOR, DC_SINGLE));

                Bias.ItfSet.DcDiffAvpiv = bicas.RCT.create_ITF_sequence(...
                    ftfCoeffs(:, :, NUMERATOR,   DC_DIFF), ...
                    ftfCoeffs(:, :, DENOMINATOR, DC_DIFF));

                Bias.ItfSet.AcLowGainAvpiv = bicas.RCT.create_ITF_sequence(...
                    ftfCoeffs(:, :, NUMERATOR,   AC_LG), ...
                    ftfCoeffs(:, :, DENOMINATOR, AC_LG));

                Bias.ItfSet.AcHighGainAvpiv = bicas.RCT.create_ITF_sequence(...
                    ftfCoeffs(:, :, NUMERATOR,   AC_HG), ...
                    ftfCoeffs(:, :, DENOMINATOR, AC_HG));
                
                % ASSERTIONS
                EJ_library.assert.all_equal(...
                   [numel(Bias.ItfSet.DcSingleAvpiv), ...
                    numel(Bias.ItfSet.DcDiffAvpiv), ...
                    numel(Bias.ItfSet.AcLowGainAvpiv), ...
                    numel(Bias.ItfSet.AcHighGainAvpiv)])
                for iEpochL = 1:nEpochL
                    %assert(Bias.ItfSet.DcSingleAvpiv{iEpochL}.eval(0) > 0, 'BICAS:calib:FailedToReadInterpretRCT', 'DC single inverted transfer function is not positive (and real) at 0 Hz. (Wrong sign?)');
                    %assert(Bias.ItfSet.DcDiffAvpiv{iEpochL}.eval(0)   > 0, 'BICAS:calib:FailedToReadInterpretRCT',   'DC diff inverted transfer function is not positive (and real) at 0 Hz. (Wrong sign?)');
                    % Unsure if assertion makes sense for AC, or possibly even for DC.
                    % 2020-03-10: This criterion is not true for AC high-gain transfer function fit now used (but does for AC diff low-gain).
                end
                
                %==========================================================================
                % ASSERTIONS: All variables NOT based on tfCoeffs/TRANSFER_FUNCTION_COEFFS
                %==========================================================================
                bicas.proc_utils.assert_zv_Epoch(Bias.epochL)
                bicas.proc_utils.assert_zv_Epoch(Bias.epochH)
                validateattributes(Bias.epochL, {'numeric'}, {'increasing'})
                validateattributes(Bias.epochH, {'numeric'}, {'increasing'})

                assert(ndims(Bias.Current.offsetsAAmpere)    == 2)
                assert(size( Bias.Current.offsetsAAmpere, 1) == nEpochL)
                assert(size( Bias.Current.offsetsAAmpere, 2) == 3)
                assert(ndims(Bias.Current.gainsAapt)         == 2)
                assert(size( Bias.Current.gainsAapt, 1)      == nEpochL)
                assert(size( Bias.Current.gainsAapt, 2)      == 3)
                assert(ndims(Bias.dcSingleOffsetsAVolt)      == 2)
                assert(size( Bias.dcSingleOffsetsAVolt, 1)   == nEpochH)
                assert(size( Bias.dcSingleOffsetsAVolt, 2)   == 3)
                for fn = fieldnames(Bias.DcDiffOffsets)'
                    assert(iscolumn(Bias.DcDiffOffsets.(fn{1}))           )
                    assert(length(  Bias.DcDiffOffsets.(fn{1})) == nEpochH)
                end
                
            catch Exc1
                Exc2 = MException('BICAS:calib:FailedToReadInterpretRCT', 'Error when interpreting calibration file (BIAS RCT) "%s"', filePath);
                Exc2 = Exc2.addCause(Exc1);
                throw(Exc2)
                %error('BICAS:calib:FailedToReadInterpretRCT', 'Error when interpreting calibration file (BIAS RCT) "%s"', filePath)
            end
        end



        % LfrItfIvptTable : {iLsf}{iBlts}. Table of LFR TFs.
        %                   iLsf=1..3 : iBlts=1..5 for BLTS 1-5
        %                   iLsf=4    : iBlts=1..3 for BIAS 1-3
        function LfrItfIvptTable = read_LFR_RCT(filePath)
            Do = dataobj(filePath);
            
            try
                % ASSUMPTION: Exactly 1 CDF record.
                % IMPLEMENTATION NOTE: Does not want to rely one dataobj special behaviour for 1 record case
                % ==> Remove leading singleton dimensions, much assertions.

                % NOTE: There are separate TFs for each BLTS channel, not just separate LFR sampling frequencies, i.e.
                % there are 5+5+5+3 TFs (but only 1 frequency table/LSF, since they are recycled).
                % NOTE: The assignment of indices here effectively determines the translation between array index and
                % LFR Sampling Frequency (LSF). This is NOT the same as the values in the LFR zVar FREQ.
                freqTableHz{1}  = shiftdim(Do.data.Freqs_F0.data);    % NOTE: Index {iLsf}.
                freqTableHz{2}  = shiftdim(Do.data.Freqs_F1.data);
                freqTableHz{3}  = shiftdim(Do.data.Freqs_F2.data);
                freqTableHz{4}  = shiftdim(Do.data.Freqs_F3.data);

                amplTableTpiv{1} = shiftdim(Do.data.TF_BIAS_12345_amplitude_F0.data);
                amplTableTpiv{2} = shiftdim(Do.data.TF_BIAS_12345_amplitude_F1.data);
                amplTableTpiv{3} = shiftdim(Do.data.TF_BIAS_12345_amplitude_F2.data);
                amplTableTpiv{4} = shiftdim(Do.data.TF_BIAS_123_amplitude_F3.data);

                phaseTableDeg{1} = shiftdim(Do.data.TF_BIAS_12345_phase_F0.data);
                phaseTableDeg{2} = shiftdim(Do.data.TF_BIAS_12345_phase_F1.data);
                phaseTableDeg{3} = shiftdim(Do.data.TF_BIAS_12345_phase_F2.data);
                phaseTableDeg{4} = shiftdim(Do.data.TF_BIAS_123_phase_F3.data);

                for iLsf = 1:4
                    if iLsf ~= 4
                        nBltsMax = 5;
                    else
                        nBltsMax = 3;
                    end

                    % NOTE: Values for the specific LSF, hence the prefix.
                    lsfFreqTableHz   = freqTableHz{iLsf};
                    lsfAmplTableTpiv = amplTableTpiv{iLsf};
                    lsfPhaseTableDeg = phaseTableDeg{iLsf};

                    % ASSERTIONS: Check CDF array sizes, and implicitly that the CDF format is the expected one.
                    assert(iscolumn(freqTableHz{iLsf}))
                    
                    assert(ndims(lsfAmplTableTpiv) == 2)
                    assert(ndims(lsfPhaseTableDeg) == 2)
                    assert(size( lsfAmplTableTpiv, 1) >= bicas.RCT.TF_TABLE_MIN_LENGTH)
                    assert(size( lsfPhaseTableDeg, 1) >= bicas.RCT.TF_TABLE_MIN_LENGTH)
                    assert(size( lsfAmplTableTpiv, 2) == nBltsMax)
                    assert(size( lsfPhaseTableDeg, 2) == nBltsMax)

                    for iBlts = 1:nBltsMax
                        
                        lsfBltsFreqTableHz   = lsfFreqTableHz;
                        lsfBltsAmplTableTpiv = lsfAmplTableTpiv(:, iBlts);
                        lsfBltsPhaseTableDeg = lsfPhaseTableDeg(:, iBlts);

                        % NOTE: INVERTS the tabulated TF.
                        %   NOTE: This requires negating the phase too.
                        ItfIvpt = EJ_library.utils.tabulated_transform(...
                            lsfBltsFreqTableHz * 2*pi, ...
                            1 ./ lsfBltsAmplTableTpiv, ...
                            - deg2rad(lsfBltsPhaseTableDeg));
                        
                        % ASSERTION: ITF
                        assert(~ItfIvpt.toward_zero_at_high_freq())
                        
                        LfrItfIvptTable{iLsf}{iBlts} = ItfIvpt;
                    end
                end
                
            catch Exc1
                Exc2 = MException('BICAS:calib:FailedToReadInterpretRCT', 'Error when interpreting calibration file (LFR team''s RCT for BIAS/BICAS) "%s"', filePath);
                Exc2 = Exc2.addCause(Exc1);
                throw(Exc2);
            end
        end
        
        
        
        function tdsCwfFactorsIvpt = read_TDS_CWF_RCT(filePath)
            
            Do = dataobj(filePath);
            
            try                
                % NOTE: Undocumented in CDF: zVar CALIBRATION_TABLE is volt/count for just multiplying the TDS signal (for
                % this kind of data). Is not a frequency-dependent transfer function.
                
                % ASSUMPTION: Exactly 1 CDF record.
                % IMPLEMENTATION NOTE: Does not want to rely one dataobj special behaviour for 1 record case
                % ==> Remove leading singleton dimensions, much assertions.
                
                tdsCwfFactorsIvpt = shiftdim(Do.data.CALIBRATION_TABLE.data);
                
                % ASSERTIONS: Check CDF array sizes, no change in format.
                assert(iscolumn(tdsCwfFactorsIvpt))
                assert(size(    tdsCwfFactorsIvpt, 1) == 3)
                
            catch Exc1
                Exc2 = MException('BICAS:calib:FailedToReadInterpretRCT', 'Error when interpreting calibration file (TDS team''s LFM CWF RCT for BIAS/BICAS) "%s"', filePath);
                Exc2 = Exc2.addCause(Exc1);
                throw(Exc2);
            end
        end
        
        
        
        function TdsRswfItfIvptList = read_TDS_RSWF_RCT(filePath)
            
            Do = dataobj(filePath);
            
            try
                % ASSUMPTION: Exactly 1 CDF record.
                % IMPLEMENTATION NOTE: Does not want to rely one dataobj special behaviour for 1 record case
                % ==> Remove leading singleton dimensions, much assertions.
                freqsHz  = shiftdim(Do.data.CALIBRATION_FREQUENCY.data);
                amplIvpt = shiftdim(Do.data.CALIBRATION_AMPLITUDE.data);
                phaseDeg = shiftdim(Do.data.CALIBRATION_PHASE.data);
                
                % ASSERTIONS: Check CDF array sizes, no change in format.
                assert(iscolumn(freqsHz));                
                assert(ndims(amplIvpt)    == 2)
                assert(ndims(phaseDeg)    == 2)
                assert(size( amplIvpt, 1) == 3)
                assert(size( phaseDeg, 1) == 3)
                assert(size( amplIvpt, 2) >= bicas.RCT.TF_TABLE_MIN_LENGTH)
                assert(size( phaseDeg, 2) >= bicas.RCT.TF_TABLE_MIN_LENGTH)

                EJ_library.assert.all_equal([...
                    length(freqsHz), ...
                    size(amplIvpt,  2), ...
                    size(phaseDeg, 2) ]);

                for iBlts = 1:3
                    ItfIvpt = EJ_library.utils.tabulated_transform(...
                        freqsHz * 2*pi, ...
                        amplIvpt(        iBlts, :), ...
                        deg2rad(phaseDeg(iBlts, :)));

                    % ASSERTION: INVERTED TF
                    assert(~ItfIvpt.toward_zero_at_high_freq(), ...
                        ['TDS RSWF transfer function appears to go toward zero at high frequencies. Has it not been', ...
                        ' inverted/made backward in time, i.e. does it not describe physical output-to-physical input?'])

                    TdsRswfItfIvptList{iBlts} = ItfIvpt;
                end

            catch Exc1
                Exc2 = MException('BICAS:calib:FailedToReadInterpretRCT', ...
                    'Error when interpreting calibration file (TDS team''s LFM RSWF RCT for BIAS/BICAS) "%s"', filePath);
                Exc2 = Exc2.addCause(Exc1);
                throw(Exc2);
            end
        end



    end    %methods(Static, Access=public)
    
    
    
    methods(Static, Access=private)



        % Utility function
        %
        % Function for normalizing the indices of dataobj zVariables.
        % dataobj zVariable arrays have different meanings for their indices depending on whether there are one record
        % or many. If there is one record, then there is not record index. If there are multiple records, then the first
        % index represents the record number. This function inserts a size-one index as the first index.
        % 
        % DO   = dataobj(...)
        % data = Do.data.TRANSFER_FUNCTION_COEFFS.data
        %
        % NOTE: Not well tested on different types of zvar array sizes.
        % 
        function data = norm_do_zv(DataobjZVar)
            % PROPOSAL: Move to utils.
            % PROPOSAL: Shorter name:
            %   norm_dataobj_zvar
            %   norm_do_zv_data
            %   norm_do_zv
            
            data = DataobjZVar.data;            
            
            if DataobjZVar.nrec == 1
                %nDims = ndims(data);
                %order = [nDims + 1, 1:nDims];
                %data = permute(data, order);
                data = shiftdim(data, -1);
            end
        end



        % Utility function to simplify read_BIAS_RCT. Arguments correspond to zVariables in BIAS RCT.
        %
        % NOTE: Arguments describe FTFs. Return value describes ITFs.
        %
        %
        % ARGUMENTS
        % =========
        % ftfNumCoeffs, ftfDenomCoeffs : 2D matrix of numerator/denominator coefficients for a sequence of FTFs.
        % ItfArray                     : Cell array of ITF (rational_func_transform).
        %
        % RETURN VALUE
        % ============
        % ItfArray : 1D cell array of EJ_library.utils.rational_func_transform.
        %
        function ItfArray = create_ITF_sequence(ftfNumCoeffs, ftfDenomCoeffs)
            % ASSERTIONS
            assert(size(ftfNumCoeffs, 1) == size(ftfDenomCoeffs, 1))
            % The last FTF denominator coefficient (highest index, for which the value is non-zero) must be =1.
            assert(...
                ftfDenomCoeffs(find(ftfDenomCoeffs, 1, 'last')) == 1, ...
                'BICAS:calib:FailedToReadInterpretRCT', ...
                ['RCT should contain forward transfer function (FTF) denominator coefficients,', ...
                ' where the highest-order (non-zero) coefficient is NOT one as expected.'])

            ItfArray = {};
            
            for i = 1:size(ftfNumCoeffs, 1)
                
                % IMPORTANT NOTE: Invert TF: FTF --> ITF
                Itf = EJ_library.utils.rational_func_transform(...
                    ftfDenomCoeffs(i,:), ...
                    ftfNumCoeffs(i,:));
                
                % ASSERTIONS
                assert(Itf.has_real_impulse_response())
                % Assert ITF. Can not set proper error message.
                assert(~Itf.zero_in_high_freq_limit(), 'BICAS:calib:FailedToReadInterpretRCT', ...
                    'Transfer function is not inverted, i.e. not physical OUTput-to-INput.')
                
                ItfArray{end+1} = Itf;
            end
        end

        

    end    %methods(Static, Access=public)

end
