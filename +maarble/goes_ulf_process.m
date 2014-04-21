%download file
folder='/Users/yuri/Documents/MATLAB/MAARBLE/GOES/';
scId = 'g12'; % Spacecraft ID
flagPlot = true;
flagPC12 = false;
flagPC35 = true;
flagExport = true;

for year=2007:2007
for month=1:1
  monthStr = sprintf('%02d',month);
  for day=2:2
    %clear variables
    clearvars -EXCEPT day monthStr year folder folder_url scId flagPlot flagPC12 flagPC35 flagExport
    dayStr = sprintf('%02d',day);
    
    filename_url=sprintf(...
      '%s%i%s%s%i%s%s%s','http://cdaweb.gsfc.nasa.gov/pub/data/goes/goes12/mag_l2/',...
      year,'/','g12_l2_mag_',year,monthStr,dayStr,'_v01.cdf');
    filename=sprintf('%s%s%i%s%s', folder,...
      'g12_l2_mag_',year,monthStr,dayStr,'_v01.cdf');
    
    if exist(filename,'file')==0
      [f, status]=urlwrite(filename_url, filename);
      display(strcat('downloading ', filename));
    end
    if exist(filename,'file')~=0
      display('processing file');
      display(filename);
      % read in Bgsm
      d=dataobj(filename);
      geiB = getmat(d,'g12_b_gei');
      geiR = getmat(d,'g12_pos_gei');
      % convert everything to GSE
      B = irf.geocentric_coordinate_transformation(geiB,'gei>gse');
      R = irf.geocentric_coordinate_transformation(geiR,'gei>gse');
      
      tint = B([1 end],1)';
      tint = [floor(tint(1)/60) ceil(tint(2)/60)]*60;
      % Extend time interval by these ranges to avoid edge effects
      DT_PC5 = 80*60; DT_PC2 = 120;
      
      fsamp=1/median(diff(B(:,1)));
      bf = irf_filt(B,0,1/600,fsamp,5);
      t_1min = ((tint(1)-DT_PC5):60:(tint(end)+DT_PC5))';
      B0_1MIN = irf_resamp(bf,t_1min); %clear bf
      facMatrix = irf_convert_fac([],B0_1MIN,R);
      
      for prod=[12 35]
        if (prod==12 && flagPC12) || (prod==35 && flagPC35)
          prodStr = num2str(prod);
          disp(['processing PC' prodStr])
          ebsp = ...
            irf_ebsp([],B,[],B0_1MIN,R,['pc' prodStr],...
            'fac','polarization','noresamp','fullB=dB','facMatrix',facMatrix);
          if flagPlot
            limByDopStruct = struct('type','low','val',0.7,'param','dop','comp',1);
            limByPlanarityStruct = struct('type','low','val',0.6,'param','planarity','comp',1);
            limBSsumStruct = struct('type','low','val',.05,'param','bb_xxyyzzss','comp',4);
            params = {{'bb_xxyyzzss',1:3,{limBSsumStruct}},...
              {'dop'},{'planarity'},...
              {'ellipticity',[],{limByDopStruct,limByPlanarityStruct}},...
              {'k_tp',[],{limByDopStruct,limByPlanarityStruct}}};
            
            h = irf_pl_ebsp(ebsp,params);
            irf_zoom(h,'x',tint)
            title(h(1),['GOES-' scId ', ' irf_disp_iso_range(tint,1)])
            set(gcf,'paperpositionmode','auto')
            print('-dpng',['GOES_' scId '_MAARBLE_ULF_PC' prodStr '_' irf_fname(tint,5)])
          end
          if flagExport
            maarble.export(ebsp,tint,scId,['pc' prodStr])
          end
        end
      end

      % Export FAC matrix & position
      if flagExport
        [facMatrix.t,idxTlim]=irf_tlim(facMatrix.t,tint);
        facMatrix.rotMatrix = facMatrix.rotMatrix(idxTlim,:,:);
        facMatrix.r = facMatrix.r(idxTlim,:);
        maarble.export(facMatrix,tint,scId)
      end
    end
  end
end
end