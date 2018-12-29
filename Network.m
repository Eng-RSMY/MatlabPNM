classdef Network < handle & Fluids
    %Network Summary of this class goes here
    %   This class contain nodes and links of the network
    
    properties
        Nodes
        Links
        xDimension
        yDimension
        zDimension
        numberOfLinks
        numberOfNodes
        
        Porosity
        totalFlowRate
        absolutePermeability
        poreVolume
        Sw_drain
        Pc_drain_curve
        
    end
    
    methods
        %% Cunstructor function
        function obj = Network(fileName)
            %Network Construct an instance of this class
            %   Detailed explanation goes here
            
%             fileName = 'Berea';
            
            % Opening the files
            link_1_fileID = fopen(strcat(fileName, '_link1.dat'));
            obj.numberOfLinks = str2num(fgetl(link_1_fileID));
            link_2_fileID = fopen(strcat(fileName, '_link2.dat'));
            
            node_2_fileID = fopen(strcat(fileName, '_node2.dat'));            
            node_1_fileID = fopen(strcat(fileName, '_node1.dat'));
            temp = str2num(fgetl(node_1_fileID));
            obj.numberOfNodes = temp(1);
            
            % Network dimension
            obj.xDimension = temp(2);
            obj.yDimension = temp(3);
            obj.zDimension = temp(4);
            
            % Initializing Nodes and Links parameters
            obj.Nodes = cell(obj.numberOfNodes,1);
            obj.Links = cell(obj.numberOfLinks,1);
            
            % 
            for i = 1:obj.numberOfNodes
                node_1_values = str2num(fgetl(node_1_fileID));
                node_2_values = str2num(fgetl(node_2_fileID));
                obj.Nodes{i} = Node(node_1_values(1),... %pore index
                                    node_1_values(2),... % pore x coordinate
                                    node_1_values(3),... % pore y coordinate
                                    node_1_values(4),... % pore z coordinate
                                    node_1_values(5),... %pore connection number
                                    node_1_values(6:end),... % inlet-outlet status and connected link index
                                    node_2_values(2),... % pore volume
                                    node_2_values(3),... % pore radius  
                                    node_2_values(4),... % pore shape factor 
                                    node_2_values(5)); % pore clay volume               
            end        
            
            for i = 1:obj.numberOfLinks
               link_1_values = str2num(fgetl(link_1_fileID));
               link_2_values = str2num(fgetl(link_2_fileID));
               obj.Links{i} = Link(link_1_values(1),... %index 
                                    link_1_values(2),... %pore1Index,... 
                                    link_1_values(3),... %pore2Index,...
                                    link_1_values(4),... %radius,...
                                    link_1_values(5),... %shapeFactor,...
                                    link_1_values(6),... %length,...
                                    link_2_values(4),... %pore1Length,...
                                    link_2_values(5),... %pore2Length,...
                                    link_2_values(6),... %linkLength,...
                                    link_2_values(7),... %volume,...
                                    link_2_values(8)); %clayVolume
            end
            
            %closing the files
            fclose(link_1_fileID); fclose(link_2_fileID);
            fclose(node_1_fileID); fclose(node_2_fileID);    
            
        end
        %% Porosity calculation
        function obj = calculatePorosity(obj)
            nodesVolume = 0;
            linksVolume = 0;
            for ii = 1:obj.numberOfNodes
                nodesVolume = nodesVolume + (obj.Nodes{ii}.volume);
            end
            for ii = 1:obj.numberOfLinks
                linksVolume = linksVolume + (obj.Links{ii}.volume);   
            end
            obj.Porosity = (linksVolume + nodesVolume) / (obj.xDimension * obj.yDimension * obj.zDimension);  
            obj.poreVolume = linksVolume + nodesVolume;
        end       
        %% Pressure distribution calculation        
        function pressureDistribution (obj, inletPressure, outletPressure)
            % pressureDistribution Summary of this method goes here
            %   Detailed explanation goes here
            Factor = zeros(obj.numberOfNodes, obj.numberOfNodes);
            B = zeros(obj.numberOfNodes, 1);  
            
            for ii = 1:obj.numberOfLinks
                
                node1Index = obj.Links{ii}.pore1Index;
                node2Index = obj.Links{ii}.pore2Index;

                % if the link is connected to inlet (index of node 1 is -1 which does not exist) 
                if obj.Links{ii}.isInlet
                    nodeLinkSystemConductance = ((obj.Links{ii}.linkLength /...
                        obj.Links{ii}.conductance) +...
                        0.5 *...
                        ((obj.Links{ii}.pore2Length / obj.Nodes{node2Index}.conductance)))^-1;
                    
                    Factor(node2Index, node2Index) = Factor(node2Index, node2Index) + nodeLinkSystemConductance;
                    B(node2Index) = nodeLinkSystemConductance * inletPressure;
                % if the link is connected to outlet (index of node 2 is 0 which does not exist)
                elseif obj.Links{ii}.isOutlet
                     nodeLinkSystemConductance = ((obj.Links{ii}.linkLength /...
                        obj.Links{ii}.conductance) +...
                        0.5 *...
                        ((obj.Links{ii}.pore1Length / obj.Nodes{node1Index}.conductance)))^-1;
                    Factor(node1Index, node1Index) = Factor(node1Index, node1Index) + nodeLinkSystemConductance;
                    B(node1Index) = nodeLinkSystemConductance * outletPressure;
                    
                %if the link is neither inlet nor outlet    
                else
                    nodeLinkSystemConductance = ((obj.Links{ii}.linkLength /...
                        obj.Links{ii}.conductance) +...
                        0.5 *...
                        ((obj.Links{ii}.pore1Length / obj.Nodes{node1Index}.conductance) +...
                        (obj.Links{ii}.pore2Length / obj.Nodes{node2Index}.conductance)))^-1;   
                
                    Factor(node1Index, node1Index) = Factor(node1Index, node1Index) + nodeLinkSystemConductance;
                    Factor(node2Index, node2Index) = Factor(node2Index, node2Index) + nodeLinkSystemConductance;
                    Factor(node1Index, node2Index) = Factor(node1Index, node2Index) - nodeLinkSystemConductance;
                    Factor(node2Index, node1Index) = Factor(node2Index, node1Index) - nodeLinkSystemConductance;
                   
                end     
            end
            
            % using Preconditioned conjugate gradients method to solve the
            % pressure distribution 
            nodesPressure = pcg(Factor,B,1e-3,300);
            
            %assign the pressure values to each node
            for ii = 1:obj.numberOfNodes
                obj.Nodes{ii}.waterPressure = nodesPressure(ii);      
            end
            
            %assign pressure values to links, since the surface whci
            %flowrate is calculated through might pass through the links
            for ii = 1:obj.numberOfLinks
                if obj.Links{ii}.isInlet
                    obj.Links{ii}.waterPressure =...
                        obj.Nodes{obj.Links{ii}.pore2Index}.waterPressure;
                elseif obj.Links{ii}.isOutlet
                    obj.Links{ii}.waterPressure =...
                        obj.Nodes{obj.Links{ii}.pore1Index}.waterPressure;                    
                else
                    obj.Links{ii}.waterPressure =...
                        (obj.Nodes{obj.Links{ii}.pore1Index}.waterPressure + ...
                        obj.Nodes{obj.Links{ii}.pore2Index}.waterPressure) / 2;
                end
            end
        end
        
        %% Conductance Calculation
         function calculateConductance(obj, Pc)           
            for i = 1:obj.numberOfNodes
                if obj.Nodes{i}.occupancy == 'B' %Node was occupied by oil
                    [obj.Nodes{i}.waterCrossSectionArea, obj.Nodes{i}.waterConductance] =...
                        obj.Nodes{i}.calculateWaterConductance(obj, Pc); 
                    [obj.Nodes{i}.oilCrossSectionArea, obj.Nodes{i}.oilConductance] = ...
                        obj.Nodes{i}.calculateOilConductance(obj);    
                else
                    obj.Nodes{i}.waterCrossSectionArea = obj.Nodes{i}.area;
                    obj.Nodes{i}.waterConductance = obj.Nodes{i}.conductance; 
                    obj.Nodes{i}.oilCrossSectionArea = 0;
                    obj.Nodes{i}.oilConductance = 0;  
                end
            end
            for i = 1:obj.numberOfLinks
                if obj.Links{i}.occupancy == 'B' %Link was occupied by oil
                    [obj.Links{i}.waterCrossSectionArea, obj.Links{i}.waterConductance] =...
                        obj.Links{i}.calculateWaterConductance(obj, Pc); 
                    [obj.Links{i}.oilCrossSectionArea, obj.Links{i}.oilConductance] = ...
                        obj.Links{i}.calculateOilConductance(obj);  
                else
                    obj.Links{i}.waterCrossSectionArea = obj.Links{i}.area;
                    obj.Links{i}.waterConductance = obj.Links{i}.conductance; 
                    obj.Links{i}.oilCrossSectionArea = 0;
                    obj.Links{i}.oilConductance = 0;
                end
            end            
        end
        %% Saturation and Conductance Calculation
        function Sw_drain = calculateSaturations(obj, Pc)
            calculateConductance(obj, Pc);
            % Water Saturation Calculation
            waterVolume = 0;   
            for i = 1:obj.numberOfNodes
                if obj.Nodes{i}.occupancy == 'B'
                     waterVolume = waterVolume + (obj.Nodes{i}.waterCrossSectionArea / obj.Nodes{i}.area) *...
                         obj.Nodes{i}.volume + obj.Nodes{i}.clayVolume;
                else
                     waterVolume = waterVolume + obj.Nodes{i}.volume + obj.Nodes{i}.clayVolume;
                end
            end
            for i = 1:obj.numberOfLinks                
                if obj.Links{i}.occupancy == 'B'
                     waterVolume = waterVolume+ (obj.Links{i}.waterCrossSectionArea / obj.Links{i}.area) * ...
                         obj.Links{i}.volume + obj.Links{i}.clayVolume + obj.Links{i}.clayVolume;
                else
                     waterVolume = waterVolume + obj.Links{i}.volume + obj.Links{i}.clayVolume;
                end  
            end  
            Sw_drain = waterVolume / obj.poreVolume;            
        end
        %% This function calculates the flow rate for each phase in the netwrok
        function calculateFlowRate(obj)
            % location of the surface whcih the flow rate should be
            % calculated through is the half distance of the network
            surfaceLocation = obj.xDimension / 2;
            flowRate = 0;
            
            %search through all the links
            for ii = 1:obj.numberOfLinks
                %the link should not be nether inlet nor outlet becasue it
                %makes problem in the index of the connected nodes
                if ~obj.Links{ii}.isInlet && ~obj.Links{ii}.isOutlet
                    
                    node1Index = obj.Links{ii}.pore1Index;
                    node2Index = obj.Links{ii}.pore2Index;
                   %if the two connected nodes pass through the sufrace
                    %count the flow of fluid passing the link connecting
                    %them
                    if obj.Nodes{node1Index}.x_coordinate < surfaceLocation && ...
                            obj.Nodes{node2Index}.x_coordinate > surfaceLocation   
                        
                        %calculate the conductivity of the linkNode system
                        nodeLinkSystemConductance = ((obj.Links{ii}.linkLength /...
                            obj.Links{ii}.conductance) +...
                            0.5 *...
                            ((obj.Links{ii}.pore1Length / obj.Nodes{node1Index}.conductance) +...
                            (obj.Links{ii}.pore2Length / obj.Nodes{node2Index}.conductance)))^-1;
                        
                        % calculate the flow rate of the fluid
                        flowRate = flowRate + ...
                            nodeLinkSystemConductance * ...
                            (obj.Nodes{node1Index}.waterPressure - ...
                            obj.Nodes{node2Index}.waterPressure);
                        
                    end
                end 
            end
            obj.totalFlowRate = flowRate;           
        end
        %% Calculate AbsolutePermeability 
        function calculateAbsolutePermeability(obj)
            %AbsolutePermeability calculates the absolute permeability of
            %the network
            %   Detailed explanation goes here
            obj.pressureDistribution(1,0);
            obj.calculateFlowRate();
            % unit conversion from m2 to Darcy
            unitConvertor = 1.01325E+12;
            % for pressure difference in the formula the corresponding
            % pressure drop between the vertical surfaces should be
            % calculated (based on Piri B1 formula)
            obj.absolutePermeability = unitConvertor * obj.totalFlowRate * obj.xDimension / (obj.yDimension* obj.zDimension); %/ ()
        end
        
        %% Primary Drainage  
        function PrimaryDrainage(obj)            
            %% Network is initialy water saturated
            for i = 1:obj.numberOfNodes
                obj.Nodes{i}.occupancy = 'A';
            end
            for i = 1:obj.numberOfLinks
                obj.Links{i}.occupancy = 'A';
            end
            
             %% determining the capillary pressure level interval
             Pc_threshold = zeros(obj.numberOfLinks,1);  
             Pc_threshold_n = zeros(obj.numberOfLinks,1); 
             for i = 1:obj.numberOfLinks                
                 Pc_threshold(i) = obj.Links{i}.thresholdPressure;
             end
             
             % Pc_interval
             max_Pc = max(Pc_threshold);
             min_Pc = min(Pc_threshold);
             Pc_interval = (max_Pc - min_Pc)/40;
             Pc_drain_max = max_Pc;
             simTimes = Pc_drain_max / Pc_interval;
             fprintf('\nPc_interval is: %f \n', Pc_interval);
             fprintf('Pc_drain_max is: %f \n', Pc_drain_max);
             fprintf('simTimes is: %f \n', simTimes);                
             Pc = 0;   
             t = 1;
             obj.Sw_drain(t,1) = 1; 
             obj.Pc_drain_curve(t,1) = 0;
             % Filling inletNodes by oil
             for i = 1:obj.numberOfNodes
                 if obj.Nodes{i}.isInlet                          
                     obj.Nodes{i}.occupancy = 'B';                   
                 end
             end        
             while Pc < Pc_drain_max              
             t = t + 1;    
             % Pc Step Calculation 
             if t < 0.3*simTimes
                 Pc = Pc + 0.5*Pc_interval;  
             else 
                 Pc = Pc + Pc_interval;  
             end
             new = 0;             
             for i = 1:obj.numberOfLinks
                 node1Index = obj.Links{i}.pore1Index;
                 node2Index = obj.Links{i}.pore2Index;
                 if (obj.Links{i}.occupancy == 'A')                     
                     if obj.Links{i}.isInlet 
                         new = new+1;   
                         Pc_threshold_n(i,1)= Pc_threshold(i);
                     elseif obj.Links{i}.isOutlet && obj.Nodes{node1Index}.occupancy == 'B'                         
                         new = new+1;                     
                         Pc_threshold_n(i,1)= Pc_threshold(i);
                     elseif ~obj.Links{i}.isInlet && ~obj.Links{i}.isOutlet
                         if obj.Nodes{node1Index}.occupancy == 'B' || obj.Nodes{node2Index}.occupancy == 'B'                         
                             new = new+1;                     
                             Pc_threshold_n(i,1)= Pc_threshold(i);
                         end
                     end
                 end
             end
             while new > 0
                 %check & sort Links based on Pc_Threshold
                 [Pc_th, ix] = sort(Pc_threshold_n(1:end), 1);
                 throat_list = ix;
                 index = 12545-new+1;
                 
                 if obj.Links{throat_list(index)}.occupancy == 'A' && Pc_threshold_n(throat_list(index)) <= Pc
                     obj.Links{throat_list(index)}.occupancy = 'B';
                     node1Index = obj.Links{throat_list(index)}.pore1Index;
                     node2Index = obj.Links{throat_list(index)}.pore2Index;
                     % if the link is connected to inlet (index of node 1 is -1 which does not exist) 
                     if obj.Links{throat_list(index)}.isInlet
                         node_index = node2Index;
                         if obj.Nodes{node_index}.occupancy == 'A'
                             obj.Nodes{node_index}.occupancy = 'B';
                             Pc_threshold_n(obj.Nodes{node_index}.connectedLinks)= Pc_threshold(obj.Nodes{node_index}.connectedLinks);                             
                             new = new + obj.Nodes{node_index}.connectionNumber;
                         end
                         
                         % if the link is connected to outlet (index of node 2 is 0 which does not exist)
                     elseif obj.Links{throat_list(index)}.isOutlet
                         
                         %if the link is neither inlet nor outlet
                     else
                         if obj.Nodes{node1Index}.occupancy == 'A'
                             obj.Nodes{node1Index}.occupancy = 'B';                                 
                             Pc_threshold_n(obj.Nodes{node1Index}.connectedLinks)= Pc_threshold(obj.Nodes{node1Index}.connectedLinks);                         
                             new = new + obj.Nodes{node1Index}.connectionNumber;
                         end
                         if obj.Nodes{node2Index}.occupancy == 'A'
                             obj.Nodes{node2Index}.occupancy = 'B';
                             Pc_threshold_n(obj.Nodes{node2Index}.connectedLinks)= Pc_threshold(obj.Nodes{node2Index}.connectedLinks);
                             new = new + obj.Nodes{node2Index}.connectionNumber;
                         end
                     end
                 end
                 Pc_threshold_n(throat_list(index))=0;
                 new = new-1;
             end
             
             %% Updating element saturations and conductances
             obj.Sw_drain(t,1) = calculateSaturations(obj, Pc);            
             
             %% Preparing Pc , Sw & Kr data                     
             obj.Pc_drain_curve(t,1) = Pc*0.000145037738;  
             
             %% Relative Permeability Calculation
             % [kr_oil(t,1),kr_water(t,1)] = k_rel(1,0);            
             
             end
             
             plot(obj.Sw_drain,obj.Pc_drain_curve,'--r')
             title('Drainage Cappilary Pressure Curves')
             xlabel('Sw')
             xlim([0 1.05])
             ylabel('Pc (Pa)')
             legend('Drainage Pc')      
        end
        %% vtk file generation
        function vtkOutput(obj)
            vtkFileID = fopen('output.vtk','w');
            if vtkFileID == -1
                error('Cannot open file for writing.');
            end
            title = 'output';
            fprintf ( vtkFileID, '# vtk DataFile Version 2.0\n' );
            fprintf ( vtkFileID, '%s\n', title );
            fprintf ( vtkFileID, 'ASCII\n' );
            fprintf ( vtkFileID, '\n' );
            fprintf ( vtkFileID, 'DATASET POLYDATA\n' );
            fprintf ( vtkFileID, 'POINTS %d double\n', obj.numberOfNodes );
            for i = 1:obj.numberOfNodes
                fprintf( vtkFileID,'%d %d %d \n', obj.Nodes{i}.x_coordinate, obj.Nodes{i}.y_coordinate, obj.Nodes{i}.z_coordinate );
            end
            
        end
    end
end

