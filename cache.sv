// ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Name:	cache.sv																								//
//																													//
// Subject:	Microprocessor System Design																			//
//																													//	
// Authors:	Kirtan Mehta , Mohammad Suheb Zammer, Punit Patel, Suryansh Jain										//
// Guide:		Professor Mark Faust																				//
// Date:		Dec 5, 2017																							//		
//																													//				
// Portland State University																						//					
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

module cache #(
	parameter K 				= 2**10,
   	parameter Address_bits  	= 32, 
   	parameter Ways_data      	= 4,	
   	parameter Sets      		= 16 * K,
   	parameter Ways_ins      	= 2,
	parameter Byte_offset 		= 64,
	parameter  Tracefile		="trace_prof"
);
parameter Index_bits 		= $clog2(Sets);
parameter Byte_offset_bits 	= $clog2(Byte_offset);
parameter Tag_bits 			= (Address_bits)-(Index_bits-Byte_offset_bits);

logic 	[1:0]Way_cuurent;
integer trace; 
logic 	[Address_bits-1:0] Address;
logic 	[3:0] Command;
logic 	[Index_bits-1 :0] Index;
logic 	[Tag_bits -1 :0] Tag;
logic 	[Byte_offset_bits - 1 :0] Byte;
integer temp_display;
logic 	Result, Found;

bit 	[$clog2(Ways_data)-1:0] Ways_data_store;
bit 	[$clog2(Ways_ins)-1:0] Ways_ins_store;
bit 	[$clog2(Ways_data)-1:0] Ways_current_data;
bit 	[$clog2(Ways_ins)-1:0] Ways_current_ins;

parameter READDATA_L1  			= 4'd0;
parameter WRITEDATA_L1      	= 4'd1;
parameter READINS_L1 	    	= 4'd2;
parameter INVALIDATE_FROM_L2 	= 4'd3;
parameter DATAREQ_FROM_L2 		= 4'd4;
parameter RESET            		= 4'd8;
parameter PRINTALL			 	= 4'd9; 

typedef enum bit[1:0]{      
 Invalid 	= 2'b00,
 Shared 	= 2'b01, 
 Modified 	= 2'b10, 
 Exclusive 	= 2'b11} MESI_state;

 MESI_state CurrentState;

//------------------------reading the trace file ---------------------------------------------------
initial 
begin
	ClearCache();
    trace = $fopen(Tracefile , "r");
	while (!$feof(trace))
	begin
        temp_display = $fscanf(trace, "%h %h\n",Command,Address);
        {Tag,Index,Byte} = Address;
    
		case (Command)

			READDATA_L1:   
			begin
				`ifdef mode2
					$display (" Op = %d, Address = %h, Set = %h, Tag = %h,", Command,Address, Index, Tag); 
				`endif
				function0(Tag, Index);
			end   
			
			WRITEDATA_L1:
			begin
				`ifdef mode2
					$display (" Op = %d, Address = %h, Set = %h, Tag = %h,", Command,Address, Index, Tag);
				`endif
				function1(Tag,Index);
			end

			READINS_L1:   
			begin
				`ifdef mode2
					$display (" Op = %d, Address = %h, Set = %h, Tag = %h", Command,Address, Index, Tag); 
				`endif
				function2(Tag, Index);
			end

			INVALIDATE_FROM_L2:
			begin
				`ifdef mode2
					$display (" Op = %d, Address = %f, Set = %h, Tag = %h", Command,Address, Index, Tag);
				`endif
				function3(Tag,Index);
			end       
			
			DATAREQ_FROM_L2:
			begin
				`ifdef mode2
					$display (" Op = %d, Address = %h, Set = %h, Tag = %h", Command,Address, Index, Tag);
				`endif
				function4(Tag,Index);
			end
		
			RESET:
			begin
				ClearCache();
			end

			PRINTALL:
			begin
				PRINTALL_CONTENTS();
			end

		endcase
	
	end

	UpdateCacheHitRatio_Data();
	UpdateCacheHitRatio_Ins();

	`ifdef mode0
		$display(" CacheIteration \t \t = %d \n \n CacheRead of Data  \t \t = %d \n CacheMISS of Data \t \t = %d \n CacheHit of Data \t \t = %d \n CacheWrite of Data \t \t = %d \n CacheHITratio of Data \t = \t %f \n \n CacheRead of Instruction \t = %d \n CacheMISS of Instruction \t = %d \n CacheHit of Instruction \t = %d \n CacheHitRatio of Instruction  = \t %f \n", CacheIterations , CacheReadCounter_Data, CacheMissCounter_Data, CacheHitCounter_Data, CacheWriteCounter_Data, CacheHitRatio_Data, CacheReadCounter_Ins, CacheMissCounter_Ins, CacheHitCounter_Ins, CacheHitRatio_Ins);
	`endif

	`ifdef mode1
		$display(" CacheIteration \t \t = %d \n \n CacheRead of Data  \t \t = %d \n CacheMISS of Data \t \t = %d \n CacheHit of Data \t \t = %d \n CacheWrite of Data \t \t = %d \n CacheHITratio of Data \t = \t %f \n \n CacheRead of Instruction \t = %d \n CacheMISS of Instruction \t = %d \n CacheHit of Instruction \t = %d \n CacheHitRatio of Instruction  = \t %f \n", CacheIterations , CacheReadCounter_Data, CacheMissCounter_Data, CacheHitCounter_Data, CacheWriteCounter_Data, CacheHitRatio_Data, CacheReadCounter_Ins, CacheMissCounter_Ins, CacheHitCounter_Ins, CacheHitRatio_Ins);
	`endif

	`ifdef mode2
		$display(" CacheIteration \t \t = %d \n \n CacheRead of Data  \t \t = %d \n CacheMISS of Data \t \t = %d \n CacheHit of Data \t \t = %d \n CacheWrite of Data \t \t = %d \n CacheHITratio of Data \t = \t %f \n \n CacheRead of Instruction \t = %d \n CacheMISS of Instruction \t = %d \n CacheHit of Instruction \t = %d \n CacheHitRatio of Instruction  = \t %f \n", CacheIterations , CacheReadCounter_Data, CacheMissCounter_Data, CacheHitCounter_Data, CacheWriteCounter_Data, CacheHitRatio_Data, CacheReadCounter_Ins, CacheMissCounter_Ins, CacheHitCounter_Ins, CacheHitRatio_Ins);
	`endif
	
	`ifdef mode2
		$display("End of line was detected.");
	`endif

	$finish;															// To end the simulation and Close QuestaSim
end

//-------------------------------------------------------------------------------------Cache Structure--------------------------------------------------------------------------------------------------//
typedef struct packed
    {
        MESI_state MESI_bits;
        bit [$clog2(Ways_data)-1:0]LRU_bits;
        bit [Tag_bits-1:0] Tag_bits;
    } Cacheline_data;

Cacheline_data [Sets-1:0][Ways_data-1:0] Cache_data; 

typedef struct packed
    {
        MESI_state MESI_bits;
        bit [$clog2(Ways_ins)-1:0]LRU_bits;
        bit [Tag_bits-1:0] Tag_bits;    
    } Cacheline_ins;

Cacheline_ins [Sets-1:0][Ways_ins-1:0]Cache_ins; 




////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

//-----------------------------------------------------------------------------Functions for counters----------------------------------------------------------------------------------------------//

int unsigned CacheHitCounter_Data = 0;
int unsigned CacheMissCounter_Data = 0;
int unsigned CacheReadCounter_Data = 0;
int unsigned CacheWriteCounter_Data = 0;

real CacheHitCounter_Ins = 0;
real CacheMissCounter_Ins = 0;
int unsigned CacheReadCounter_Ins = 0;

real CacheHitRatio_Data;// = 1;
real CacheHitRatio_Ins; // = 1;

longint unsigned CacheIterations = 0;


//--------------------------------------------------------Increment every cache Access
task IncCacheIterations();
	CacheIterations = CacheIterations + 1;
		`ifdef mode2
			$display ("CacheIterations= %d \n",CacheIterations);
		`endif
endtask


//------------------------------------------------------CacheHitCounter of Data Cache
task IncCacheHitCounter_Data();
	CacheHitCounter_Data = CacheHitCounter_Data+ 1;
		`ifdef mode2
			$display ("CacheHitCounter of Data Cache= %d \n",CacheHitCounter_Data);
		`endif
endtask


//-------------------------------------------increment CacheMissCounter of Data Cache
task IncCacheMissCounter_Data();
	CacheMissCounter_Data = CacheMissCounter_Data + 1;
		`ifdef mode2		
			$display ("CacheMissCounter of Data Cache = %d \n",CacheMissCounter_Data);
		`endif
endtask


//--------------------------------------------increment CacheReadCounter of Data Cache
task IncCacheReadCounter_Data();
	CacheReadCounter_Data = CacheReadCounter_Data + 1;
		`ifdef mode2
			$display ("CacheReadCounter of Data Cache= %d \n",CacheReadCounter_Data);
		`endif
endtask 

//-----------------------------------------increment CacheWriteCounter of Data Cache
task IncCacheWriteCounter_Data();
	CacheWriteCounter_Data = CacheWriteCounter_Data + 1;
		`ifdef mode2
			$display ("CacheWriteCounter of Data Cache = %d \n",CacheWriteCounter_Data);
		`endif
endtask

//----------------------------------- increment CacheHitCounter of Instruction Cache
task IncCacheHitCounter_Ins();
	CacheHitCounter_Ins = CacheHitCounter_Ins + 1;
		`ifdef mode2
			$display ("CacheHitCounter of Instruction Cache= %d \n",CacheHitCounter_Ins);
		`endif
endtask

//-----------------------------------increment CacheMissCounter of  Instruction Cache
task IncCacheMissCounter_Ins();
	CacheMissCounter_Ins = CacheMissCounter_Ins + 1;
		`ifdef mode2		
			$display ("CacheMissCounter of Instruction Cache = %d \n",CacheMissCounter_Ins);
		`endif
endtask

//---------------------------------------increment CacheReadCounter of  Instruction Cache
task IncCacheReadCounter_Ins();
	CacheReadCounter_Ins = CacheReadCounter_Ins + 1;
		`ifdef mode2
			$display ("CacheReadCounter of Instruction Cache = %d \n",CacheReadCounter_Ins);
		`endif
endtask 

//-------------------------------------- Update the Cache Hit Ratio of Data Cache
task UpdateCacheHitRatio_Data(); 

	CacheHitRatio_Data = (real'(CacheHitCounter_Data)/(real'(CacheHitCounter_Data) + real'(CacheMissCounter_Data))) * 100.00;
	`ifdef mode2
	
		$display("CacheHitRatio for Data Cache= %f \n" ,CacheHitRatio_Data);
	
	`endif
endtask

//---------------------------------------- Update the Cache Hit Ratio of Instruction Cache
task UpdateCacheHitRatio_Ins();     
		CacheHitRatio_Ins = (real'(CacheHitCounter_Ins)/(real'(CacheHitCounter_Ins) + real'(CacheMissCounter_Ins))) * 100.00;
        `ifdef mode2
			$display("CacheHitRatio for Instruction cache = %f \n" ,CacheHitRatio_Ins );
		`endif
endtask

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////



//-----------------------------------------------------------------------------Task to clear the cache and Reset------------------------------------------------------------------------------------------------------//

task ClearCache();
	IncCacheIterations();
	
	for(int i=0; i< Sets; i++) 
	begin

		for(int j=0; j< Ways_data; j++) 
		begin
			Cache_data[i][j].Tag_bits 	= '0;
			Cache_data[i][j].LRU_bits 	= {$clog2(Ways_data){1'b1}};
			Cache_data[i][j].MESI_bits 	= Invalid;
		end
	
	end

	for(int i=0; i< Sets; i++) 
	begin
		
		for(int j=0; j< Ways_ins; j++) 
		begin	
			Cache_ins[i][j].Tag_bits 	= '0;
			Cache_ins[i][j].LRU_bits 	= {$clog2(Ways_ins){1'b1}};
			Cache_ins[i][j].MESI_bits 	= Invalid;
		end
	
	end

endtask:ClearCache

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


//------------------------------------------------------------------------------- Task to print all the valid contents of the Cache------------------------------------------------------------------------------------//
task PRINTALL_CONTENTS();
	bit already;
	
	$display("*********************\nStart of Data Cache");
	for(int i=0; i< Sets; i++)
	begin
		for(int j=0; j< Ways_data; j++) 
		begin
			if(Cache_data[i][j].MESI_bits != Invalid)
			begin
				if(!already)
				begin
				$display("*********************\nIndex = %h", i);
				already = 1;
				end
				$display("--------------------------------");
				$display(" Way = %d \n Tag = %h \n MESI = %s \n LRU = %b", j, Cache_data[i][j].Tag_bits, Cache_data[i][j].MESI_bits, Cache_data[i][j].LRU_bits);
			end
		end
		already = 0;
	end
	$display("********************\nEnd of Data cache.\n********************\n\n");
	
	
	$display("*********************\nStart of Instruction Cache");
	for(int i=0; i< Sets; i++)
	begin
		for(int j=0; j< Ways_ins; j++) 
		begin
			if(Cache_ins[i][j].MESI_bits != Invalid)
			begin
				if(!already)
				begin
				$display("*********************\nIndex = %h", i);
				already = 1;
				end
				$display("--------------------------------");
				$display(" Way = %d \n Tag = %h \n MESI = %s \n LRU = %b", j, Cache_ins[i][j].Tag_bits, Cache_ins[i][j].MESI_bits, Cache_ins[i][j].LRU_bits);
			end
		end
		already = 0;
	end
	$display("********************\nEnd of Instruction cache.\n********************");

endtask

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


//---------------------------------------------------------------------Funtion0: Read data from L1 Data Cache------------------------------------------------------------------------//
task function0 ( logic [Tag_bits -1 :0] Tag, logic [Index_bits-1:0] Index); 
	
	IncCacheIterations();
	IncCacheReadCounter_Data();
	
	Address_Valid_Data (Index, Tag, Ways_data_store, Result, Ways_current_data, CurrentState);
	if (Result == 1)
	begin
		IncCacheHitCounter_Data();
		UpdateLRUBits_data(Index, Ways_data_store, Ways_current_data );
		Cache_data[Index][Ways_current_data].MESI_bits = Cache_data[Index][Ways_current_data].MESI_bits;
	end
	
	else
	begin
		IncCacheMissCounter_Data();
		
		`ifdef mode2
			$display ("CacheMiss...., iTag=%0h, iIndex=%0h, Ways_store=%0h, CurrentState=%s ",Tag, Index, Ways_data_store,Cache_data[Index][Ways_data].MESI_bits);
		`endif
		
		Found = 0;
		Find_invalind_line_data(Index , Ways_data_store , Found , Ways_current_data, CurrentState );
		
		if (Found)
		begin
			Allocate_line_data(Index,Tag, Ways_current_data);
			
			`ifdef mode2
				$display("Read from L2 address %h" , {Tag,Index, {Byte_offset_bits{1'b0}}});
			`endif
			
			`ifdef mode1
				$display("Read from L2 address %h" , {Tag,Index, {Byte_offset_bits{1'b0}}});
			`endif

			UpdateLRUBits_data(Index, Ways_data_store, Ways_current_data );
			Cache_data[Index][Ways_current_data].MESI_bits = Shared;
		end

		else
		begin
			eviction_data(Index, Ways_current_data);
			Allocate_line_data(Index, Tag, Ways_current_data);
			
			`ifdef mode2
				$display("Read from L2 address %h" , {Tag,Index, {Byte_offset_bits{1'b0}}});
			`endif

			`ifdef mode1
				$display("Read from L2 address %h" , {Tag,Index, {Byte_offset_bits{1'b0}}});
			`endif
			
			UpdateLRUBits_data(Index, Ways_data_store, Ways_current_data );
		end
	
	end
	`ifdef mode2
	for (int i =0; i< Ways_data; i++)
	begin
		
		$display("Tag= %h ,Way number = %d , LRU bits = %d , MESI_STATE = %s", Cache_data[Index][i].Tag_bits, i ,Cache_data[Index][i].LRU_bits, Cache_data[Index][i].MESI_bits );
	end
	`endif

endtask

//------------------------------------------------------------------------------------------------Funtion1: Write data to L1 Data Cache------------------------------------------------------------------------//
task function1 ( logic [Tag_bits -1 :0] Tag, logic [Index_bits-1:0] Index);
	
	IncCacheIterations();
	IncCacheWriteCounter_Data();
	
	Address_Valid_Data (Index, Tag, Ways_data_store, Result, Ways_current_data, CurrentState);
	
	if (Result == 1)
	begin
		IncCacheHitCounter_Data();
		
		UpdateLRUBits_data(Index, Ways_data_store, Ways_current_data );
		
		if ((Cache_data[Index][Ways_current_data].MESI_bits == Exclusive) | (Cache_data[Index][Ways_current_data].MESI_bits == Modified) )
		begin
			Cache_data[Index][Ways_current_data].MESI_bits = Modified;
		end
		
		else if (Cache_data[Index][Ways_current_data].MESI_bits == Shared)
		begin
			Cache_data[Index][Ways_current_data].MESI_bits = Exclusive;
			
			`ifdef mode2
				$display("Write to L2 address %h" , {Tag,Index, {Byte_offset_bits{1'b0}}}); 
			`endif

			`ifdef mode1
				$display("Write to L2 address %h" , {Tag,Index, {Byte_offset_bits{1'b0}}}); 
			`endif
		end
	end
	
	else
	begin
		IncCacheMissCounter_Data();
		Find_invalind_line_data(Index , Ways_data_store , Found , Ways_current_data, CurrentState );
	
		if (Found)
		begin
			Allocate_line_data(Index,Tag, Ways_current_data);
			
			`ifdef mode2
				$display("Read for ownership from L2 %h ", Address);
				$display("Write to L2 address %h" , {Tag,Index, {Byte_offset_bits{1'b0}}}); 
			`endif

			`ifdef mode1
				$display("Read for ownership from L2 %h ", Address);
				$display("Write to L2 address %h" , {Tag,Index, {Byte_offset_bits{1'b0}}}); 
			`endif

			UpdateLRUBits_data(Index, Ways_data_store, Ways_current_data );
			Cache_data[Index][Ways_current_data].MESI_bits = Exclusive;
		end

		else
		begin
			eviction_data(Index, Ways_current_data);
			Allocate_line_data(Index, Tag, Ways_current_data);
			
			`ifdef mode2
				$display("Read for ownership from L2 %h ", Address);
				$display("Write to L2 address %h" , {Tag,Index, {Byte_offset_bits{1'b0}}}); 
			`endif

			`ifdef mode1
				$display("Read for ownership from L2 %h ", Address);
				$display("Write to L2 address %h" , {Tag,Index, {Byte_offset_bits{1'b0}}}); 
			`endif
			
			UpdateLRUBits_data(Index, Ways_data_store, Ways_current_data );
			Cache_data[Index][Ways_current_data].MESI_bits = Exclusive;
		end
	
	end
	
	`ifdef mode2
		for (int i =0; i< Ways_data; i++)
		begin
			$display("Tag= %h ,Way number = %d , LRU bits = %d , MESI_STATE = %s", Cache_data[Index][i].Tag_bits, i ,Cache_data[Index][i].LRU_bits, Cache_data[Index][i].MESI_bits );
		end
	`endif

endtask

//------------------------------------------------------------------------------------------------Funtion2: Instruction Fetch------------------------------------------------------------------------//
task function2 ( logic [Tag_bits -1 :0] Tag, logic [Index_bits-1:0] Index); 
	IncCacheIterations();
	IncCacheReadCounter_Ins();
	
	Address_Valid_Ins (Index, Tag, Ways_ins_store, Result, Ways_current_ins, CurrentState);
	
	if (Result == 1)
	begin
		IncCacheHitCounter_Ins();
		UpdateLRUBits_ins(Index, Ways_ins_store, Ways_current_ins );
		Cache_ins[Index][Ways_current_ins].MESI_bits = Shared;
	end
	
	else
	begin
		IncCacheMissCounter_Ins();
		
		`ifdef mode2
			$display ("CacheMiss...., Tag=%0h, Index=%0h, Ways_store=%0h, CurrentState=%s ",Tag, Index, Ways_ins_store,Cache_ins[Index][Ways_ins].MESI_bits);
		`endif
		
		Find_invalind_line_ins(Index , Ways_ins_store , Found , Ways_current_ins, CurrentState );
		
		if (Found)
		begin
			Allocate_line_ins(Index,Tag, Ways_current_ins);
			
			`ifdef mode2
				$display("Read from L2 address %h" , {Tag,Index, {Byte_offset_bits{1'b0}}});
			`endif

			`ifdef mode1
				$display("Read from L2 address %h" , {Tag,Index, {Byte_offset_bits{1'b0}}});
			`endif
			
			UpdateLRUBits_ins(Index, Ways_ins_store, Ways_current_ins );
			Cache_ins[Index][Ways_current_ins].MESI_bits = Shared;
		end

		else
		begin
			eviction_ins(Index, Ways_current_ins);
			Allocate_line_ins(Index, Tag, Ways_current_ins);
			
			`ifdef mode2
				$display("Read from L2 address %h" , {Tag,Index, {Byte_offset_bits{1'b0}}});
			`endif

			`ifdef mode1
				$display("Read from L2 address %h" , {Tag,Index, {Byte_offset_bits{1'b0}}});
			`endif
			
			UpdateLRUBits_ins(Index, Ways_ins_store, Ways_current_ins );

		end
	end
	
	`ifdef mode2
		for (int i =0; i< Ways_ins; i++)
		begin
			$display("Tag= %h ,Way number = %d , LRU bits = %d , MESI_State = %s",Cache_ins[Index][i].Tag_bits, i ,Cache_ins[Index][i].LRU_bits, Cache_ins[Index][i].MESI_bits );	
		end
	`endif

endtask

//------------------------------------------------------------------------------------------------Funtion3: Send Invalidate command from L2 cache------------------------------------------------------------------------//
task function3 ( logic [Tag_bits -1 :0] Tag, logic [Index_bits-1:0] Index);
	IncCacheIterations();
	
	Address_Valid_Data (Index, Tag, Ways_data_store, Result, Ways_current_data, CurrentState);
	if (Result == 1)
	begin
	 	if ((Cache_data[Index][Ways_current_data].MESI_bits == Modified) | (Cache_data[Index][Ways_current_data].MESI_bits == Exclusive))
		begin
			`ifdef mode2
				$display("WARNING!!!  The data is in %s state in L1", Cache_data[Index][Ways_current_data].MESI_bits);
			`endif		
		end

		else if ((Cache_data[Index][Ways_current_data].MESI_bits == Shared))
		begin
			Cache_data[Index][Ways_current_data].MESI_bits = Invalid;
		end
	end

	`ifdef mode2
		for (int i =0; i< Ways_data; i++)
		begin
				$display("Tag= %h ,Way number = %d , LRU bits = %d , MESI_State = %s",Cache_data[Index][i].Tag_bits, i ,Cache_data[Index][i].LRU_bits, Cache_data[Index][i].MESI_bits );	
		end
	`endif

endtask

//------------------------------------------------------------------------------------------------Function4: Data Request from L2 Cache------------------------------------------------------------------------//
task function4 ( logic [Tag_bits -1 :0] Tag, logic [Index_bits-1:0] Index); 
	IncCacheIterations();
	
	Address_Valid_Data (Index, Tag, Ways_data_store, Result, Ways_current_data, CurrentState);
	if (Result == 1)
	 begin
	 	if (Cache_data[Index][Ways_current_data].MESI_bits == Exclusive)
		begin
			Cache_data[Index][Ways_current_data].MESI_bits = Shared;
		end

		else if (Cache_data[Index][Ways_current_data].MESI_bits == Modified)
		begin
			`ifdef mode1	
				$display("Return data to L2 address %h" , {Tag,Index, {Byte_offset_bits{1'b0}}});
			`endif

			`ifdef mode2	
				$display("Return data to L2 address %h" , {Tag,Index, {Byte_offset_bits{1'b0}}});
			`endif
			Cache_data[Index][Ways_current_data].MESI_bits = Shared;
		end

		else if (Cache_data[Index][Ways_current_data].MESI_bits == Shared)
		begin
			`ifdef mode2
				$display("WARNING!!! Data already present in L2 Address");
			`endif		
		end
	
	end

	`ifdef mode2
		for (int i =0; i< Ways_data; i++)
		begin
			$display("Tag= %h ,Way number = %d , LRU bits = %d , MESI_State = %s",Cache_data[Index][i].Tag_bits, i ,Cache_data[Index][i].LRU_bits, Cache_data[Index][i].MESI_bits );
		end
	`endif
endtask


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////



//---------------------------------------------------------------Check Whether the Address is valid or not by chacking the INVALID MESI STATES and Tag bits--------------------------------------------------------------//

task automatic Address_Valid_Data (logic [Index_bits-1 :0] iIndex, logic [Tag_bits -1 :0] iTag, ref bit [$clog2(Ways_data)-1:0] Ways_data_store, output logic Result , ref bit [$clog2(Ways_data)-1:0] Ways_current_data , output MESI_state CurrentState );
	Result = 0;

	for (int j = 0;  j < Ways_data ; j++)
	begin

		if (Cache_data[iIndex][j].MESI_bits != Invalid) 
		begin	
			
			if (Cache_data[iIndex][j].Tag_bits == iTag)
			begin 
			
				Ways_current_data = j;
				Result = 1; 
				`ifdef mode2
					$display ("CacheHit...., Tag=%0h, Index=%0h, Way_data =%d, CurrentState=%s ",iTag, iIndex,Ways_current_data,Cache_data[iIndex][Ways_current_data].MESI_bits);
				`endif
				return;
			end
				
		end
	end		

endtask

task automatic Address_Valid_Ins (logic [Index_bits-1 :0] iIndex, logic [Tag_bits -1 :0] iTag, ref bit [$clog2(Ways_ins)-1:0] Ways_ins_store, output logic Result , ref bit [$clog2(Ways_ins)-1:0] Ways_current_ins , output MESI_state CurrentState );
	Result = 0;

	for (int j = 0;  j < Ways_ins ; j++)
	begin
		if (Cache_ins[iIndex][j].MESI_bits != Invalid) 
		begin`ifdef mode2	
				$display("Return data to L2 address %h" , {iTag,iIndex, {Byte_offset_bits{1'b0}}});
			`endif
			
			if (Cache_ins[iIndex][j].Tag_bits == iTag)
			begin 
			
				Ways_current_ins = j;
				Result = 1; 
				
				`ifdef mode2
					$display ("CacheHit...., Tag=%0h, Index=%0h, Way_ins =%d, CurrentState=%s ",iTag, iIndex,Ways_current_ins, Cache_ins[iIndex][Ways_current_ins].MESI_bits);
				 `endif
				
				return;
			end
				
		end
		
	end		

endtask

//-------------------------------------------------------------Find Iinvalid line by checking its MESI BITS INVALID----------------------------------------------------------------------------------------------------//

task automatic Find_invalind_line_data (logic [Index_bits-1:0] iIndex, ref bit [$clog2(Ways_data)-1:0] Ways_data_store, output logic Found, ref bit [$clog2(Ways_data)-1:0] Ways_current_data, output MESI_state CurrentState);
	Found =  0;
	
	for (int i =0; i< Ways_data; i++ )
	begin
		
		if (Cache_data[iIndex][i].MESI_bits == Invalid)
		begin
			Ways_current_data = i;
			Found = 1;
			return;
		end
	end
	`ifdef mode2	
//				$display("Return data to L2 address %h" , {iTag,iIndex, {Byte_offset_bits{1'b0}}});
	`endif

endtask

task automatic Find_invalind_line_ins (logic [Index_bits - 1:0] iIndex, ref bit [$clog2(Ways_ins)-1:0] Ways_ins_store, output logic Found, ref bit [$clog2(Ways_ins)-1:0] Ways_current_ins, output MESI_state CurrentState);
	Found =  0;
	
	for (int i =0; i< Ways_ins; i++ )
	begin
		
		if (Cache_ins[iIndex][i].MESI_bits == Invalid)
		begin
			Ways_current_ins = i;
			Found = 1;
			return;
		end
	end

endtask

//------------------------------------------------------------------------------Allocation of Line for giving the TAG to be added------------------------------------------------------------------------------------------//

task automatic Allocate_line_data (logic [Index_bits -1:0] iIndex, logic [Tag_bits -1 :0] iTag, ref bit [$clog2(Ways_data)-1:0] Ways_current_data);

	Cache_data[iIndex][Ways_current_data].Tag_bits = iTag;
	UpdateLRUBits_data(iIndex, Ways_data_store , Ways_current_data);
	Cache_data[iIndex][Ways_current_data].MESI_bits = Shared;

endtask

task automatic Allocate_line_ins (logic [Index_bits -1 :0] iIndex, logic [Tag_bits -1 :0] iTag, ref bit [$clog2(Ways_ins)-1:0] Ways_current_ins);

	Cache_ins[iIndex][Ways_current_ins].Tag_bits = iTag;
	UpdateLRUBits_ins(iIndex, Ways_ins_store , Ways_current_ins);
	Cache_ins[iIndex][Ways_current_ins].MESI_bits = Shared;

endtask

//---------------------------------------------------------------------------------------------Eviction of line and adding a new line----------------------------------------------------------------------------------------//


task automatic eviction_data(logic [Index_bits -1:0] iIndex, ref bit [$clog2(Ways_data)-1:0] Ways_current_data);

	for (int i =0; i< Ways_data; i++ )
	begin
		if (Cache_data[iIndex][i].LRU_bits ==  {($clog2(Ways_data)){1'b1}})
		begin
			if (Cache_data[iIndex][i].MESI_bits == Modified)
			begin
				`ifdef mode2
					$display("Write to L2 Address %h ", {Cache_data[iIndex][i].Tag_bits,iIndex,{ Byte_offset_bits{1'b0}}} );
				`endif

				`ifdef mode1
					$display("Write to L2 Address %h ", {Cache_data[iIndex][i].Tag_bits,iIndex,{ Byte_offset_bits{1'b0}}} );
				`endif
				
				Ways_current_data = i;
			end

			else
			begin
				Ways_current_data = i;
			end

		end

	end

endtask

task automatic eviction_ins(logic [Index_bits - 1:0] iIndex, ref bit [$clog2(Ways_ins)-1:0] Ways_current_ins);

	for (int i =0; i< Ways_ins; i++ )
	begin
		if (Cache_ins[iIndex][i].LRU_bits ==  {$clog2(Ways_ins){1'b1}})
		begin
			if (Cache_ins[iIndex][i].MESI_bits == Modified)
			begin
				`ifdef mode2
					$display("Write to L2 Address %h ", {Cache_ins[iIndex][i].Tag_bits,iIndex,{ Byte_offset_bits{1'b0}}} );
				`endif

				`ifdef mode1
					$display("Write to L2 Address %h ", {Cache_ins[iIndex][i].Tag_bits,iIndex,{ Byte_offset_bits{1'b0}}} );
				`endif				
				Ways_current_ins = i;
			end

			else
			begin
				Ways_current_ins = i;
			end

		end

	end

endtask


/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


//--------------------------------------------------------------------Update LRU bits--------------------------------------------------------------------------------------------------------------------------------//

task automatic UpdateLRUBits_data(logic [Index_bits-1:0]iIndex, ref bit [$clog2(Ways_data)-1:0] Ways_data_store ,ref bit [$clog2(Ways_data)-1:0] Ways_current_data );
	bit [$clog2(Ways_data)-1:0]temp;
	temp = Cache_data[iIndex][Ways_current_data].LRU_bits;
	
	for (int j = 0; j < Ways_data ; j++)
	begin
		
		if(Cache_data[iIndex][j].LRU_bits < temp) 
		begin
			Cache_data[iIndex][j].LRU_bits = Cache_data[iIndex][j].LRU_bits + 1'b1;
		end

	end
	Cache_data[iIndex][Ways_current_data].LRU_bits = '0;
endtask : UpdateLRUBits_data


task automatic UpdateLRUBits_ins(logic [Index_bits-1:0]iIndex, ref bit [$clog2(Ways_ins)-1:0] Ways_ins_store,ref bit [$clog2(Ways_ins)-1:0] Ways_current_ins );
	bit [$clog2(Ways_ins)-1:0]temp;
	temp = Cache_ins[iIndex][Ways_current_ins].LRU_bits;
	
	for (int j = 0; j < Ways_ins ; j++)
	begin
		
		if(Cache_ins[iIndex][j].LRU_bits < temp) 
		begin
			Cache_ins[iIndex][j].LRU_bits = Cache_ins[iIndex][j].LRU_bits + 1'b1;
		
		end
	end
	
	Cache_ins[iIndex][Ways_current_ins].LRU_bits = '0;
endtask : UpdateLRUBits_ins


endmodule


//---------------------------------------------------------------------------End of CODE------------------------------------------------------------------------------------------------------------------------//


//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
