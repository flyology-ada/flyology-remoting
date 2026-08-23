package body Flyology.Remoting.Endpoints.Directories is
   use type Endpoint_Word;
   use type Identities.Node_ID;
   use type Identities.Node_Reference;

   protected body Directory_State is
      procedure Try_Claim
        (Claimed_Slot : out Endpoint_Slot;
         Claimed_Generation : out Endpoint_Generation;
         Result : out Claim_Result)
      is
      begin
         for Index in Slot_Index loop
            if not Active (Index) and then Generations (Index) /= Endpoint_Generation'Last then
               Generations (Index) := Generations (Index) + 1;
               Active (Index) := True;
               Active_Count := Active_Count + 1;
               Claimed_Slot := Endpoint_Slot (Index);
               Claimed_Generation := Generations (Index);
               Result := Endpoint_Claimed;
               return;
            end if;
         end loop;

         Claimed_Slot := No_Endpoint_Slot;
         Claimed_Generation := No_Endpoint_Generation;
         Result := (if Active_Count = 0 then Generation_Exhausted else Directory_Full);
      end Try_Claim;

      procedure Release
        (Released_Slot : Endpoint_Slot;
         Released_Generation : Endpoint_Generation;
         Was_Current : out Boolean)
      is
         Value : constant Endpoint_Word := To_Word (Released_Slot);
      begin
         Was_Current := False;
         if Value = 0 or else Value > Endpoint_Word (Capacity) then
            return;
         end if;

         declare
            Index : constant Slot_Index := Slot_Index (Value);
         begin
            if Active (Index) and then Generations (Index) = Released_Generation then
               Active (Index) := False;
               Active_Count := Active_Count - 1;
               Was_Current := True;
            end if;
         end;
      end Release;

      function Is_Current
        (Current_Slot : Endpoint_Slot; Current_Generation : Endpoint_Generation) return Boolean
      is
         Value : constant Endpoint_Word := To_Word (Current_Slot);
      begin
         if Value = 0 or else Value > Endpoint_Word (Capacity) then
            return False;
         end if;

         declare
            Index : constant Slot_Index := Slot_Index (Value);
         begin
            return Active (Index) and then Generations (Index) = Current_Generation;
         end;
      end Is_Current;

      function Current return Directory_Snapshot is
         Exhausted_Count : Natural := 0;
      begin
         for Index in Slot_Index loop
            if not Active (Index) and then Generations (Index) = Endpoint_Generation'Last then
               Exhausted_Count := Exhausted_Count + 1;
            end if;
         end loop;

         return
           (Active    => Active_Count,
            Available => Capacity - Active_Count - Exhausted_Count,
            Exhausted => Exhausted_Count);
      end Current;
   end Directory_State;

   function Create (Owner : Identities.Node_Reference) return Directory is
   begin
      if not Identities.Is_Valid (Owner) then
         raise Invalid_Owner with "endpoint directory requires a valid node incarnation";
      end if;

      return Result : Directory do
         Result.Owner_Node := Owner;
      end return;
   end Create;

   function Owner (Item : Directory) return Identities.Node_Reference is
     (Item.Owner_Node);

   procedure Try_Claim
     (Item : in out Directory; Reference : out Endpoint_Reference; Result : out Claim_Result)
   is
      Claimed_Slot       : Endpoint_Slot;
      Claimed_Generation : Endpoint_Generation;
   begin
      Item.State.Try_Claim (Claimed_Slot, Claimed_Generation, Result);
      if Result = Endpoint_Claimed then
         Reference := Make_Endpoint_Reference (Item.Owner_Node, Claimed_Slot, Claimed_Generation);
      else
         Reference := No_Endpoint;
      end if;
   end Try_Claim;

   procedure Release
     (Item : in out Directory; Reference : Endpoint_Reference; Result : out Release_Result)
   is
      Reference_Node : constant Identities.Node_Reference := Destination_Node (Reference);
      Was_Current    : Boolean;
   begin
      if not Is_Valid (Reference) then
         Result := Stale_Endpoint;
      elsif Identities.Stable_ID (Reference_Node) /= Identities.Stable_ID (Item.Owner_Node) then
         Result := Foreign_Node;
      elsif Reference_Node /= Item.Owner_Node then
         Result := Stale_Incarnation;
      else
         Item.State.Release (Slot (Reference), Generation (Reference), Was_Current);
         Result := (if Was_Current then Released else Stale_Endpoint);
      end if;
   end Release;

   function Is_Current (Item : Directory; Reference : Endpoint_Reference) return Boolean is
     (Is_Valid (Reference)
      and then Destination_Node (Reference) = Item.Owner_Node
      and then Item.State.Is_Current (Slot (Reference), Generation (Reference)));

   function Current (Item : Directory) return Directory_Snapshot is
     (Item.State.Current);

end Flyology.Remoting.Endpoints.Directories;
