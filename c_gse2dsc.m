function [y] = c_gse2dsc( x, spin_axis, direction, db )
% C_GSE2DSC  Convert vector between GSE and DSC reference systems.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
%  Usage:
%  function [out] = c_gse2dsc( inp, spin_axis, [direction],[db])
%  function [out] = c_gse2dsc( inp, [isdat_epoch sc], [direction],[db])
%  function [out] = c_gse2dsc( inp, sc, [direction],[db])
%
%     Convert vector from GSE into DSC reference system.
%     From STAFF manual:
%        inp, out - vectors with 3 components,
%                   inp(:,1) is X,  inp(:,2) is Y ...
%        if more than 3 columns then columns
%                   inp(:,2) is X, inp(:,3) is Y ...
%        spin_axis = vector in GSE or ISDAT epoch.
%        direction = -1 to convert from DSC into GSE.
%        sc        = spacecraft number.
%        db        = isdat database pointer, that is db = Mat_DbOpen(DATABASE)
%
%     Assume the spin orientation does not change significantly during the
%     choosen interval. Only values at start time point is used.
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
debug_flag=0;
flag_read_isdat=0;

if nargin <  2, disp('Not enough arguments'); help c_gse2dsc; return; end
if nargin <  3, direction=1;                                          end
if nargin == 4, flag_db=1; else, flag_db=0;                           end

  % Spin_axis gives only s/c number
  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  if size(spin_axis,2) == 1
     ic        = spin_axis;
     t         = x(1,1);
     clear spin_axis;
     spin_axis = [t ic];
  end

  % Use time to get spin_axis
  %%%%%%%%%%%%%%%%%%%%%%%%%%%
  if size(spin_axis,2) == 2
     t  = spin_axis(1);
     ic = spin_axis(2);
     if exist('./maux.mat');
         c_log('load','Loading maux.mat file');
         try c_eval('load maux sc_at?_lat__CL_SP_AUX sc_at?_long__CL_SP_AUX; lat=sc_at?_lat__CL_SP_AUX; long = sc_at?_long__CL_SP_AUX;', ic);
         catch c_log('load','Loading maux.mat file failed'); flag_read_isdat=1;
         end
         if flag_read_isdat==0, % if reading maux file suceeded
             tmin = lat(1,1);
             tmax = lat(end,1);
             if (t > tmin) | (t < tmax)
                 eval( av_ssub('load maux sc_at?_lat__CL_SP_AUX sc_at?_long__CL_SP_AUX; lat=sc_at?_lat__CL_SP_AUX; long = sc_at?_long__CL_SP_AUX;', ic) );
                 latlong   = av_interp([lat long(:,2)],t);
             end
         else  % maux file from the wrong day
             disp('c_gse2dsc() OBS!!!  maux.mat from the wrong date');
             disp('                    get the right one or delete the existing one');
             disp('            I am getting attitude data from isdat instead');
             flag_read_isdat=1;
         end
     end
     if flag_read_isdat,  % try if there is SP CDF file, otherwise continue to isdat
      cdf_files=dir(['CL_SP_AUX_' epoch2yyyymmdd(t) '*']);
         switch prod(size(cdf_files))
             case 1
                 cdf_file=cdf_files.name;
                 c_log('load',['converting CDF file ' cdf_file ' -> maux.mat']);
                 cdf2mat(cdf_file,'maux.mat');
                 c_log('load',['Loading from CDF file:' cdf_file '. Next time will use maux.mat']);
                 c_eval('lat=av_read_cdf(cdf_file,{''sc_at?_lat__CL_SP_AUX''});',ic);
                 c_eval('long=av_read_cdf(cdf_file,{''sc_at?_long__CL_SP_AUX''});',ic);
                 if (t > lat(1,1)) & (t < lat(end,1)),
                     flag_read_isdat=0;
                     latlong   = av_interp([lat long(:,2)],t);
                 end
         end
     end
     if flag_read_isdat==1,  % load from isdat satellite ephemeris
      if debug_flag, disp('loading spin axis orientation from isdat database');end
       start_time=t; % time of the first point
       Dt=600; % 10 min, in file they are saved with 1 min resolution
        if flag_db==0, % open ISDAT database disco:10
          if debug_flag, disp('Starting connection to disco:10');end
          db = Mat_DbOpen('disco:10');
        end
        [tlat, lat] = isGetDataLite( db, start_time, Dt, 'CSDS_SP', 'CL', 'AUX', ['sc_at' num2str(ic) '_lat__CL_SP_AUX'], ' ', ' ',' ');
        [tlong, long] = isGetDataLite( db, start_time, Dt, 'CSDS_SP', 'CL', 'AUX', ['sc_at' num2str(ic) '_long__CL_SP_AUX'], ' ', ' ',' ');
        xxx=[double(tlat) double(lat) double(long)];
        if isempty(xxx), y=NaN; return;
        else,
          latlong=xxx(1,:);
        end
        if debug_flag, disp(['lat=' num2str(latlong(2)) '  long=' num2str(latlong(3))]); end
        if flag_db==0,
          Mat_DbClose(db);
        end
     end
     [xspin,yspin,zspin]=sph2cart(latlong(3)*pi/180,latlong(2)*pi/180,1);
     spin_axis=[xspin yspin zspin];
  end

spin_axis=spin_axis/norm(spin_axis);
if debug_flag, disp('Spin axis orientation');spin_axis, end

lx=size(x,2);
if lx > 3
 inp=x(:,[2 3 4]); % assuming first column is time
elseif lx == 3
 inp=x;
else
 disp('too few components of vector')
 exit
end

Rx=spin_axis(1);
Ry=spin_axis(2);
Rz=spin_axis(3);
a=1/sqrt(Ry^2+Rz^2);
M=[[a*(Ry^2+Rz^2) -a*Rx*Ry -a*Rx*Rz];[0 a*Rz	-a*Ry];[Rx	Ry	Rz]];
Minv=inv(M);

if direction == 1
 out=M*inp';
 out=out';
 if length(out(:,1))==1
  if debug_flag == 1,sprintf('x,y,z = %g, %g, %g [DSC]',out(1), out(2),out(3));end
 end
elseif direction==-1
 out=Minv*inp';
 out=out';
 if length(out(:,1))==1
  if debug_flag == 1, sprintf('x,y,z = %g, %g, %g [GSE]',out(1), out(2),out(3));end
 end
else
 disp('No coordinate transformation done!')
end

y=x;
if lx > 3
 y(:,[2 3 4])=out; % assuming first column is time
else
 y=out;
end


