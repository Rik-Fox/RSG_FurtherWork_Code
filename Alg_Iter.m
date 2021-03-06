function Alg_Iter(N_post, N_sr, N_algs, N_algs_sr)

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%     Inputs are:
%         N_post -> Number of posteriors to be tried
%         N_sr -> Number of stochastic seed runs
%         N_algs -> Number of trial algorithms to be compared
%         N_algs_sr -> Number of stochastic runs for each trial algorithm, starting at result of each stoch seed run

%     Main loop procedure is:
%           Healthzone >> Posterior >> Screening Method >> Currently used
%           algorithm from 2016 - 2020 (seed run) >> Trial algorithm from 2020 onwards

%     Loads in data (data.mat) and parameters (Paras_DRC100.mat, DRC specific) from Input_Data dir 
%     which must reside at the same level as the dir containing this code 
    %%% need to look up kwargs in MATLAB to allow for data to be saved in any dir, i.e. to do what it is doing now without args instruction
    %%%, input, output, default_dir_loc)   

%     Posteriors ('<healthzoneIDnumber>_Posterior.mat') are also held in Input_Data, as well as the Projections
%     results from HATMEPP data fitting up to 2016 (ProjectionICs_M4_DRC_P1_<nameofhealthzone>_IDDRC100.mat')
%     which are used as a jumping off point hence simulations start in 2016

%     Sccrening methods consist of:
%           --- taking the avg of the last 5 years of healthzone screening data and using that value for all
%           years henceforth
%           --- sampling from the last five years of healthzone screening data
%           --- take a rolling average of the previous 5 years 

%     referred to here as a seed run is a simulation instance from 2016 -
%     2020, at the end of each of these the system state is used as inital
%     conditions for N_alg_sr number of runs for each trial algorithm.
%     Yeilding N_sr*N_alg_sr simulations of each algorithm per healthzone
%     per posterior per screening projection method

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%



    input = "../Input_Data/SensSpec/MobileAlgorithms_SensSpec.csv";

    % if default_dir_loc
    %     mkdir('../'+output)
    % else
    %     mkdir(output)
    % end

    output = "../Output_Data";
    mkdir(output)

    load_Data = load('../Input_Data/Data.mat'); %Loads Bandundu data from Data directory

    %%% load in all Params, relevant or not
    load('../Input_Data/Paras_DRC100.mat', 'FittedParameters', 'FixedParameters', 'InterventionParameters', 'Strategy')

    %%% Strat0 is no RDT no VC
    ProjStrat = table2struct(Strategy('Strat0', :));

    %%% Params for all top level DRC fits
    fittedparas = FittedParameters(FittedParameters.Location == "DRC", :);

    %%% using M4 values to make it run, need to confirm correct choice
    fittedparas = fittedparas(fittedparas.Model ~= "M5M8", :);
    fittedparas = fittedparas(fittedparas.Model ~= "M7M8", :);

    %%%params specified for Bandundu (Province)
    Unique_to_Bandundu = FittedParameters(FittedParameters.Location == "P1_Bandundu", :);

    %%% find and insert/replace params for localised Province fits where needed
    for i = 1:length(Unique_to_Bandundu.Notation)

        try
            fittedparas(fittedparas.Notation == string(Unique_to_Bandundu.Notation(i)), :) = Unique_to_Bandundu(i, :);
        catch
            fittedparas = [fittedparas; Unique_to_Bandundu(i, :)];
        end

    end

    %%% used for selecting further fitted params, need array to dynamically update within loop
    HZloc = {'Z29_Kwamouth', 'Z35_Mosango', 'Z51_YasaBonga'};

    %%% used for generating screening data in different ways, need array to dynamically update within loop
    scrnames = {'Constant_Screening', 'Sampled_Screening', 'Rolling_Avg_Screening'};

    %%% pulls in output from SensSpec analysis
    Algors = readtable(input);

    HZ_N = 1;                   %%%length(HZloc);
    post_itr_N = N_post;
    scr_N = 1;                  %%% length(scrnames); % number of different methods for projecting screening data
    sr_N = N_sr;                % number of stochastic runs for period up to 2020
    alg_N = N_algs;             % number of algorithms to be trialled
    alg_sr_N = N_algs_sr;       % number of stochastic runs for each trail algorithm from 2020 onwards

    PostIDs = zeros(post_itr_N, length(HZloc));

    for hz = 1:HZ_N

        %%% pulls name and number of healthzone, loads corresponding interventions, maybe could skip?
        location = char(HZloc(:, hz)); %Identifies relevant health zone
        loc_idx = str2double(string(location(2:3)));
        loc_name = load_Data.CCLOC(loc_idx);

        loc_dir = output + '/' + location;
        mkdir(loc_dir);

        %%% find and insert/replace params for localised HealthZone fits where found, defaults to Province otherwise
        if sum(InterventionParameters.Location == string(location))
            intervention = InterventionParameters(InterventionParameters.Location == string(location), :);
        else
            intervention = InterventionParameters(InterventionParameters.Location == "P1_Bandundu", :);
        end

        %%% force no VC to happen, just in case
        intervention.VCstart = 0;
        intervention.TargetDie = 0;

        %%% loads in healthzone Posterior and ICs, data from HATMEPP, saves running pre2016 dynamics
        load('../Input_Data/' + string(loc_idx) + '_Posterior.mat', 'Posterior')
        load('../Input_Data/ProjectionICs_M4_DRC_P1_' + string(location) + '_IDDRC100.mat', 'ProjectionICs')

        FixedParameters.Location = loc_name;

        %%% Struct easier to append to
        Paras = table2struct([cell2table(num2cell(fittedparas.Initial)', 'VariableNames', fittedparas.Notation'), FixedParameters, intervention(1, 2:end)]);

        for post_itr = 1:post_itr_N

            %%% sample from ProjectionICs, as 1:1 mapping with posterior, if .PostID is used to find correct posterior, is equivalent to sampling posterior and finding its 2016 ICs

            % datasample(data, # of samples, dims)
            ICs = datasample(ProjectionICs, 1, 1, 'Replace', false);
            PostIDs(post_itr, hz) = ICs.PostID;
            posterior = Posterior(ICs.PostID, :);

            post_dir = loc_dir + '/Posterior_' + string(ICs.PostID);
            mkdir(post_dir);

            %%% find and insert/replace params for MCMC fitted values
            var_names = posterior.Properties.VariableNames;

            %%% replace relevant paras with healtzone fitted paras
            for i = 1:length(var_names)
                Paras.(string(var_names(i))) = posterior.(string(var_names(i)));
            end

            %%% reformat and selection of ICs for input into main functions
            %%% simulation output seemed to start from almost 0, looking into IC data files and they seem to be of O(1), but this may not be correct, need to clear this up
            Data_ICs = {[ICs.S_H1, ICs.S_H2, ICs.S_H3, ICs.S_H4, 0, 0], ...
                [ICs.E_H1, ICs.E_H2, ICs.E_H3, ICs.E_H4, 0, 0], ...
                [ICs.I1_H1, ICs.I1_H2, ICs.I1_H3, ICs.I1_H4, 0, 0], ...
                [ICs.I2_H1, ICs.I2_H2, ICs.I2_H3, ICs.I2_H4, 0, 0], ...
                [ICs.R_H1, ICs.R_H2, ICs.R_H3, ICs.R_H4, 0, 0], ...
                ICs.S_A, ICs.E_A, ICs.I1_A, ICs.P_V, ICs.S_V, ICs.G_V, ICs.E1_V, ICs.E2_V, ICs.E3_V, ICs.I_V};

            %%% very important, Paras.PostID is saved and is only way to ID posterior post simulation if removed from generated dir
            Paras.PostID = ICs.PostID;

            writetable(struct2table(Paras), post_dir + "/pre2016_Paras.csv")

            for scr = 1:scr_N
                scrname = char(scrnames(scr));
                scr_dir = post_dir + '/' + scrname;
                mkdir(scr_dir);

                %%% Handling screening data generation and saving

                %%% Data for getting ICs samples at 2020
                %%% load in data fresh to reset the subsequent changes we make
                Data_20 = Screening_Projection(struct('Years', load_Data.YEAR, 'N_H', load_Data.PopSize(loc_idx), 'PopSizeYear', load_Data.PopSizeYear, 'PeopleScreened', load_Data.SCREENED(loc_idx, :)), load_Data.YEAR(end) + 1:2019, scrname);

                %%% Data from current year (2020) onwards
                Data_50 = Screening_Projection(Data_20, Data_20.Years(end) + 1:2050, scrname);

                %%% concat to save, generated seperately for ease of use, transpose varibles to output useful csv
                Data4saving = struct('ModelScreeningFreq', [Data_20.ModelScreeningFreq Data_50.ModelScreeningFreq]', 'ModelScreeningTime', [Data_20.ModelScreeningTime Data_50.ModelScreeningTime]', 'ModelPeopleScreened', [Data_20.ModelPeopleScreened Data_50.ModelPeopleScreened]');

                %%% only save generated Screening Data variables as others can be seen in input data or Agg/Class data, and avoids unnecessary reshaping of single value /inconsistently shaped fields if I tried to include them elsewhere
                writetable(struct2table(Data4saving), scr_dir + "/Data.csv");

                meff = GetMeff(Data_20.N_H, Paras);
                    
                %%% Ricky Changed to have the right data as input
                [ClassesODE0, AggregateODE0] = ODEHATmodel(meff, Data_ICs, Data_20, Paras, ProjStrat);

                popODE = ClassesODE0(end, :);
                modelODE_ICs = {[popODE.S_H1, popODE.S_H2, popODE.S_H3, popODE.S_H4, 0, 0], ...
                    [popODE.E_H1, popODE.E_H2, popODE.E_H3, popODE.E_H4, 0, 0], ...
                    [popODE.I1_H1, popODE.I1_H2, popODE.I1_H3, popODE.I1_H4, 0, 0], ...
                    [popODE.I2_H1, popODE.I2_H2, popODE.I2_H3, popODE.I2_H4, 0, 0], ...
                    [popODE.R_H1, popODE.R_H2, popODE.R_H3, popODE.R_H4, 0, 0], ...
                    popODE.S_A, popODE.E_A, popODE.I1_A, popODE.P_V, popODE.S_V, popODE.G_V, popODE.E1_V, popODE.E2_V, popODE.E3_V, popODE.I_V};

                %%% stochastic runs for 2016-2020. I do not iterate algorithms over this period of time, instead run multiple realisations of algorithm projections, from end of each realisation of this time period, saves on repeating unimformative realisations.
                for sr_itr = 1:sr_N

                    sr_dir = scr_dir + '/StochRun#' + string(sr_itr);
                    mkdir(sr_dir);

                    %%% last entry refers to current practice algorithm
                    Paras.Sensitivity = Algors.MeanSens(end);
                    Paras.Specificity = Algors.MeanSpec(end);

                    %%% HAT has not been Eliminated so dont save Elim output
                    [Classes0, Aggregate0, ~] = StochasticHATmodel(meff, Data_ICs, Data_20, Paras, ProjStrat);
                    
                    %%% now use this as ICs for algorithm simulations
                    pop = Classes0(end, :);
                    model_ICs = {[pop.S_H1, pop.S_H2, pop.S_H3, pop.S_H4, 0, 0], ...
                        [pop.E_H1, pop.E_H2, pop.E_H3, pop.E_H4, 0, 0], ...
                        [pop.I1_H1, pop.I1_H2, pop.I1_H3, pop.I1_H4, 0, 0], ...
                        [pop.I2_H1, pop.I2_H2, pop.I2_H3, pop.I2_H4, 0, 0], ...
                        [pop.R_H1, pop.R_H2, pop.R_H3, pop.R_H4, 0, 0], ...
                        pop.S_A, pop.E_A, pop.I1_A, pop.P_V, pop.S_V, pop.G_V, pop.E1_V, pop.E2_V, pop.E3_V, pop.I_V};

                    %%% each algorithm
                    for alg = 1:alg_N
                        alg_dir = sr_dir + '/' + Algors.name(alg);
                        mkdir(alg_dir);

                        [ClassesODE, AggregateODE] = ODEHATmodel(meff, modelODE_ICs, Data_50, Paras, ProjStrat);

                        writetable([ClassesODE0; ClassesODE], alg_dir + "/Classes.csv", 'WriteRowNames', true);

                        writetable([AggregateODE0; AggregateODE], alg_dir + "/Aggregate.csv", 'WriteRowNames', true);

                        ElimDist = zeros(alg_sr_N, 3);

                        %%% stoch runs out to sim finish year for each alg
                        for alg_sr_itr = 1:alg_sr_N

                            alg_sr_dir = alg_dir + '/StochRun#' + string(alg_sr_itr);
                            mkdir(alg_sr_dir);

                            Paras.Sensitivity = Algors.MeanSens(alg);
                            Paras.Specificity = Algors.MeanSpec(alg);

                            [Classes, Aggregate, Elim] = StochasticHATmodel(meff, model_ICs, Data_50, Paras, ProjStrat);

                            %%% concat pre 2020 realisation with this realisation and save, could save seperate to save space but would need a way to assign what goes with which...

                            writetable([Classes0; Classes], alg_sr_dir + "/Classes.csv", 'WriteRowNames', true);

                            writetable([Aggregate0; Aggregate], alg_sr_dir + "/Aggregate.csv", 'WriteRowNames', true);

                            ElimDist(alg_sr_itr, :) = [Elim.Trans, Elim.Report, Elim.Inf];

                        end

                        writetable(array2table(ElimDist, 'VariableNames', {'TransElimYear', 'ReportElimYear', 'InfElimYear'}), alg_dir + "/ElimDist.csv");

                    end

                end

            end

        end

    end

    %%% create tables of the names of everything iterated over for use by plotting code to iteratively extract data
    alg_names = cell2table(Algors.name, 'VariableNames', {'Algorithm_Names'});
    scr_types = cell2table(scrnames', 'VariableNames', {'Screen_Types'});
    HZ = cell2table(HZloc', 'VariableNames', {'Health_Zones'});

    PostID_HZnames = string(HZloc);

    for i = 1:height(HZ)
        PostID_HZnames(i) = extractAfter(PostID_HZnames(i), "_") + "_PostIDs";
    end

    post_IDs = array2table(PostIDs, 'VariableNames', cellstr(PostID_HZnames));

    %%% pad out all varibles to longest variable
    H = max([height(alg_names) height(post_IDs) height(scr_types) height(HZ)]);

    post_IDs = [post_IDs; cell(H - height(post_IDs), width(post_IDs))];
    alg_names = [alg_names; cell(H - height(alg_names), width(alg_names))];
    scr_types = [scr_types; cell(H - height(scr_types), width(scr_types))];
    HZ = [HZ; cell(H - height(HZ), width(HZ))];

    iter_info = [HZ post_IDs scr_types alg_names];

    writetable(iter_info, "test.csv");
    writetable(iter_info, output + "/Iter_Info.csv");

    fprintf("done \n\n");
%     quit;

end
