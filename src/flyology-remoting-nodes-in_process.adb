with Flyology.Remoting.Transports;

package body Flyology.Remoting.Nodes.In_Process is
   use type Endpoints.Endpoint_Generation;
   use type Endpoints.Endpoint_Word;
   use type Identities.Node_ID;
   use type Identities.Node_Reference;
   use type Transports.Try_Receive_Result;
   use type Transports.Try_Send_Result;

   protected body Gate_State is
      procedure Try_Claim
        (Claimed_Slot       : out Endpoints.Endpoint_Slot;
         Claimed_Generation : out Endpoints.Endpoint_Generation;
         Result             : out Claim_Result)
      is
         Active_Count : Natural := 0;
      begin
         for Index in Slot_Index loop
            if not Active (Index)
              and then Endpoints.To_Word (Generations (Index)) /= Endpoints.Endpoint_Word'Last
            then
               Generations (Index) :=
                 Endpoints.Generation_From_Word (Endpoints.To_Word (Generations (Index)) + 1);
               Active (Index) := True;
               Closing (Index) := False;
               Close_Active (Index) := False;
               Pins (Index) := 0;
               Claimed_Slot := Endpoints.Slot_From_Word (Endpoints.Endpoint_Word (Index));
               Claimed_Generation := Generations (Index);
               Result := Endpoint_Claimed;
               return;
            elsif Active (Index) then
               Active_Count := Active_Count + 1;
            end if;
         end loop;

         Claimed_Slot := Endpoints.No_Endpoint_Slot;
         Claimed_Generation := Endpoints.No_Endpoint_Generation;
         Result := (if Active_Count = 0 then Generation_Exhausted else Directory_Full);
      end Try_Claim;

      procedure Try_Pin
        (Slot       : Endpoints.Endpoint_Slot;
         Generation : Endpoints.Endpoint_Generation;
         Result     : out Pin_Result;
         Held       : out Boolean)
      is
         Value : constant Endpoints.Endpoint_Word := Endpoints.To_Word (Slot);
      begin
         Held := False;
         if Value = 0 or else Value > Endpoints.Endpoint_Word (Endpoint_Capacity) then
            Result := Pin_Stale;
            return;
         end if;

         declare
            Index : constant Slot_Index := Slot_Index (Value);
         begin
            if not Active (Index) or else Generations (Index) /= Generation then
               Result := Pin_Stale;
            elsif Closing (Index) then
               Result := Pin_Closing;
            elsif Pins (Index) = Operation_Count'Last then
               Result := Pin_Limit;
            else
               Pins (Index) := Pins (Index) + 1;
               Result := Pinned;
               Held := True;
            end if;
         end;
      end Try_Pin;

      procedure Unpin (Slot : Endpoints.Endpoint_Slot; Generation : Endpoints.Endpoint_Generation) is
         Value : constant Endpoints.Endpoint_Word := Endpoints.To_Word (Slot);
      begin
         if Value = 0 or else Value > Endpoints.Endpoint_Word (Endpoint_Capacity) then
            return;
         end if;

         declare
            Index : constant Slot_Index := Slot_Index (Value);
         begin
            if Active (Index) and then Generations (Index) = Generation and then Pins (Index) > 0 then
               Pins (Index) := Pins (Index) - 1;
            end if;
         end;
      end Unpin;

      procedure Begin_Close
        (Slot       : Endpoints.Endpoint_Slot;
         Generation : Endpoints.Endpoint_Generation;
         Result     : out Begin_Close_Result;
         Held       : out Boolean)
      is
         Value : constant Endpoints.Endpoint_Word := Endpoints.To_Word (Slot);
      begin
         Held := False;
         if Value = 0 or else Value > Endpoints.Endpoint_Word (Endpoint_Capacity) then
            Result := Close_Stale;
            return;
         end if;

         declare
            Index : constant Slot_Index := Slot_Index (Value);
         begin
            if not Active (Index) or else Generations (Index) /= Generation then
               Result := Close_Stale;
            elsif Close_Active (Index) then
               Result := Close_Busy;
            else
               Closing (Index) := True;
               Close_Active (Index) := True;
               Result := Close_Begun;
               Held := True;
            end if;
         end;
      end Begin_Close;

      procedure Abandon_Close
        (Slot : Endpoints.Endpoint_Slot; Generation : Endpoints.Endpoint_Generation)
      is
         Value : constant Endpoints.Endpoint_Word := Endpoints.To_Word (Slot);
      begin
         if Value = 0 or else Value > Endpoints.Endpoint_Word (Endpoint_Capacity) then
            return;
         end if;

         declare
            Index : constant Slot_Index := Slot_Index (Value);
         begin
            if Active (Index) and then Generations (Index) = Generation and then Closing (Index) then
               Close_Active (Index) := False;
            end if;
         end;
      end Abandon_Close;

      function Is_Quiescent
        (Slot : Endpoints.Endpoint_Slot; Generation : Endpoints.Endpoint_Generation) return Boolean
      is
         Value : constant Endpoints.Endpoint_Word := Endpoints.To_Word (Slot);
      begin
         if Value = 0 or else Value > Endpoints.Endpoint_Word (Endpoint_Capacity) then
            return False;
         end if;

         declare
            Index : constant Slot_Index := Slot_Index (Value);
         begin
            return
              Active (Index)
              and then Generations (Index) = Generation
              and then Closing (Index)
              and then Close_Active (Index)
              and then Pins (Index) = 0;
         end;
      end Is_Quiescent;

      procedure Complete_Close
        (Slot : Endpoints.Endpoint_Slot; Generation : Endpoints.Endpoint_Generation)
      is
         Value : constant Endpoints.Endpoint_Word := Endpoints.To_Word (Slot);
      begin
         if Value = 0 or else Value > Endpoints.Endpoint_Word (Endpoint_Capacity) then
            return;
         end if;

         declare
            Index : constant Slot_Index := Slot_Index (Value);
         begin
            if Active (Index)
              and then Generations (Index) = Generation
              and then Closing (Index)
              and then Close_Active (Index)
              and then Pins (Index) = 0
            then
               Active (Index) := False;
               Closing (Index) := False;
               Close_Active (Index) := False;
            end if;
         end;
      end Complete_Close;

      function Is_Current
        (Slot : Endpoints.Endpoint_Slot; Generation : Endpoints.Endpoint_Generation) return Boolean
      is
         Value : constant Endpoints.Endpoint_Word := Endpoints.To_Word (Slot);
      begin
         if Value = 0 or else Value > Endpoints.Endpoint_Word (Endpoint_Capacity) then
            return False;
         end if;

         declare
            Index : constant Slot_Index := Slot_Index (Value);
         begin
            return Active (Index) and then not Closing (Index) and then Generations (Index) = Generation;
         end;
      end Is_Current;

      function Current return Node_Snapshot is
         Active_Count    : Natural := 0;
         Closing_Count   : Natural := 0;
         Exhausted_Count : Natural := 0;
      begin
         for Index in Slot_Index loop
            if Active (Index) then
               if Closing (Index) then
                  Closing_Count := Closing_Count + 1;
               else
                  Active_Count := Active_Count + 1;
               end if;
            elsif Endpoints.To_Word (Generations (Index)) = Endpoints.Endpoint_Word'Last then
               Exhausted_Count := Exhausted_Count + 1;
            end if;
         end loop;

         return
           (Active    => Active_Count,
            Closing   => Closing_Count,
            Available => Endpoint_Capacity - Active_Count - Closing_Count - Exhausted_Count,
            Exhausted => Exhausted_Count);
      end Current;
   end Gate_State;

   type Pin_Guard (State : not null access Gate_State) is
     limited new Ada.Finalization.Limited_Controlled with
   record
      Slot       : Endpoints.Endpoint_Slot := Endpoints.No_Endpoint_Slot;
      Generation : Endpoints.Endpoint_Generation := Endpoints.No_Endpoint_Generation;
      Held       : Boolean := False;
   end record;

   overriding procedure Finalize (Item : in out Pin_Guard);

   overriding procedure Finalize (Item : in out Pin_Guard) is
   begin
      if Item.Held then
         Item.State.Unpin (Item.Slot, Item.Generation);
         Item.Held := False;
      end if;
   end Finalize;

   procedure Release (Item : in out Pin_Guard) is
   begin
      Finalize (Item);
   end Release;

   type Close_Guard (State : not null access Gate_State) is
     limited new Ada.Finalization.Limited_Controlled with
   record
      Slot       : Endpoints.Endpoint_Slot := Endpoints.No_Endpoint_Slot;
      Generation : Endpoints.Endpoint_Generation := Endpoints.No_Endpoint_Generation;
      Held       : Boolean := False;
   end record;

   overriding procedure Finalize (Item : in out Close_Guard);

   overriding procedure Finalize (Item : in out Close_Guard) is
   begin
      if Item.Held then
         Item.State.Abandon_Close (Item.Slot, Item.Generation);
         Item.Held := False;
      end if;
   end Finalize;

   procedure Release (Item : in out Close_Guard) is
   begin
      Item.Held := False;
   end Release;

   function Create (Owner : Identities.Node_Reference) return Node is
   begin
      if not Identities.Is_Valid (Owner) then
         raise Invalid_Owner with "in-process node requires a valid node incarnation";
      end if;

      return Result : Node do
         Result.Owner_Node := Owner;
      end return;
   end Create;

   function Owner (Item : Node) return Identities.Node_Reference is
     (Item.Owner_Node);

   function Claim (Item : not null access Node) return Endpoint_Handle is
   begin
      return Result : Endpoint_Handle (Item) do
         declare
            Claimed_Slot       : Endpoints.Endpoint_Slot;
            Claimed_Generation : Endpoints.Endpoint_Generation;
         begin
            Item.State.Try_Claim (Claimed_Slot, Claimed_Generation, Result.Outcome);
            if Result.Outcome = Endpoint_Claimed then
               Result.Endpoint :=
                 Endpoints.Make_Endpoint_Reference
                   (Item.Owner_Node, Claimed_Slot, Claimed_Generation);
            end if;
         end;
      end return;
   end Claim;

   function Status (Item : Endpoint_Handle) return Claim_Result is
     (Item.Outcome);

   function Has_Endpoint (Item : Endpoint_Handle) return Boolean is
     (Endpoints.Is_Valid (Item.Endpoint));

   function Reference (Item : Endpoint_Handle) return Endpoints.Endpoint_Reference is
     (Item.Endpoint);

   function Local_Reference
     (Item : Node; Reference : Endpoints.Endpoint_Reference) return Try_Send_Result
   is
      Reference_Node : constant Identities.Node_Reference := Endpoints.Destination_Node (Reference);
   begin
      if not Endpoints.Is_Valid (Reference) then
         return Stale_Endpoint;
      elsif Identities.Stable_ID (Reference_Node) /= Identities.Stable_ID (Item.Owner_Node) then
         return Foreign_Node;
      elsif Reference_Node /= Item.Owner_Node then
         return Stale_Incarnation;
      else
         return Message_Accepted;
      end if;
   end Local_Reference;

   function Receive_Classification (Value : Try_Send_Result) return Try_Receive_Result is
     (case Value is
         when Foreign_Node             => Foreign_Node,
         when Stale_Incarnation        => Stale_Incarnation,
         when Stale_Endpoint           => Stale_Endpoint,
         when Endpoint_Closing         => Endpoint_Closing,
         when Local_Resource_Exhausted => Local_Resource_Exhausted,
         when Message_Accepted | Backpressure => raise Program_Error);

   procedure Pin
     (Item      : in out Node;
      Reference : Endpoints.Endpoint_Reference;
      Guard     : in out Pin_Guard;
      Result    : out Try_Send_Result)
   is
      Classification : constant Try_Send_Result := Local_Reference (Item, Reference);
      Pin_Status     : Pin_Result;
   begin
      Result := Classification;
      if Classification /= Message_Accepted then
         return;
      end if;

      Guard.Slot := Endpoints.Slot (Reference);
      Guard.Generation := Endpoints.Generation (Reference);
      Item.State.Try_Pin (Guard.Slot, Guard.Generation, Pin_Status, Guard.Held);

      Result :=
        (case Pin_Status is
            when Pinned      => Message_Accepted,
            when Pin_Closing => Endpoint_Closing,
            when Pin_Stale   => Stale_Endpoint,
            when Pin_Limit   => Local_Resource_Exhausted);
   end Pin;

   procedure Try_Send
     (Item        : in out Node;
      Destination : Endpoints.Endpoint_Reference;
      Value       : in out Writable_Payload;
      Result      : out Try_Send_Result)
   is
      Guard      : Pin_Guard (Item.State'Access);
      Lane_Result : Transports.Try_Send_Result;
   begin
      Pin (Item, Destination, Guard, Result);
      if not Guard.Held then
         return;
      end if;

      Payload_Transport.Try_Send
        (Item.Mailboxes (Slot_Index (Endpoints.To_Word (Endpoints.Slot (Destination)))),
         Value,
         Lane_Result);
      Result :=
        (case Lane_Result is
            when Transports.Message_Accepted => Message_Accepted,
            when Transports.Backpressure     => Backpressure,
            when Transports.Send_Closed      => Endpoint_Closing);
      Release (Guard);
   end Try_Send;

   procedure Try_Send
     (Item        : in out Node;
      Destination : Endpoints.Endpoint_Reference;
      Value       : in out Received_Payload;
      Result      : out Try_Send_Result)
   is
      Guard       : Pin_Guard (Item.State'Access);
      Lane_Result : Transports.Try_Send_Result;
   begin
      Pin (Item, Destination, Guard, Result);
      if not Guard.Held then
         return;
      end if;

      Payload_Transport.Try_Send
        (Item.Mailboxes (Slot_Index (Endpoints.To_Word (Endpoints.Slot (Destination)))),
         Value,
         Lane_Result);
      Result :=
        (case Lane_Result is
            when Transports.Message_Accepted => Message_Accepted,
            when Transports.Backpressure     => Backpressure,
            when Transports.Send_Closed      => Endpoint_Closing);
      Release (Guard);
   end Try_Send;

   procedure Try_Receive
     (Item     : in out Node;
      Endpoint : Endpoints.Endpoint_Reference;
      Target   : in out Received_Payload;
      Result   : out Try_Receive_Result)
   is
      Guard          : Pin_Guard (Item.State'Access);
      Send_Class     : Try_Send_Result;
      Lane_Result    : Transports.Try_Receive_Result;
   begin
      Pin (Item, Endpoint, Guard, Send_Class);
      if not Guard.Held then
         Result := Receive_Classification (Send_Class);
         return;
      end if;

      Payload_Transport.Try_Receive
        (Item.Mailboxes (Slot_Index (Endpoints.To_Word (Endpoints.Slot (Endpoint)))),
         Target,
         Lane_Result);
      Result :=
        (case Lane_Result is
            when Transports.Message_Received => Message_Received,
            when Transports.No_Message       => No_Message,
            when Transports.Receive_Closed   => Endpoint_Closing);
      Release (Guard);
   end Try_Receive;

   function Close_Classification
     (Item : Node; Reference : Endpoints.Endpoint_Reference) return Close_Result
   is
      Reference_Node : constant Identities.Node_Reference := Endpoints.Destination_Node (Reference);
   begin
      if not Endpoints.Is_Valid (Reference) then
         return Stale_Endpoint;
      elsif Identities.Stable_ID (Reference_Node) /= Identities.Stable_ID (Item.Owner_Node) then
         return Foreign_Node;
      elsif Reference_Node /= Item.Owner_Node then
         return Stale_Incarnation;
      else
         return Endpoint_Closed;
      end if;
   end Close_Classification;

   procedure Close_Endpoint
     (Item : in out Node; Endpoint : Endpoints.Endpoint_Reference; Result : out Close_Result)
   is
      Classification : constant Close_Result := Close_Classification (Item, Endpoint);
      Guard          : Close_Guard (Item.State'Access);
      Begin_Result   : Begin_Close_Result;
      Pending        : Received_Payload;
      Receive_Result : Transports.Try_Receive_Result;
      Index          : Slot_Index;
   begin
      Result := Classification;
      if Classification /= Endpoint_Closed then
         return;
      end if;

      Guard.Slot := Endpoints.Slot (Endpoint);
      Guard.Generation := Endpoints.Generation (Endpoint);
      Item.State.Begin_Close (Guard.Slot, Guard.Generation, Begin_Result, Guard.Held);

      case Begin_Result is
         when Close_Stale =>
            Result := Stale_Endpoint;
            return;
         when Close_Busy =>
            Result := Close_Already_In_Progress;
            return;
         when Close_Begun =>
            null;
      end case;

      while not Item.State.Is_Quiescent (Guard.Slot, Guard.Generation) loop
         delay 0.0;
      end loop;

      Index := Slot_Index (Endpoints.To_Word (Guard.Slot));
      loop
         Payload_Transport.Try_Receive (Item.Mailboxes (Index), Pending, Receive_Result);
         exit when Receive_Result /= Transports.Message_Received;
         Payload_Transport.Release (Pending);
      end loop;

      Item.State.Complete_Close (Guard.Slot, Guard.Generation);
      Release (Guard);
      Result := Endpoint_Closed;
   end Close_Endpoint;

   procedure Close (Item : in out Endpoint_Handle; Result : out Close_Result) is
   begin
      if not Has_Endpoint (Item) then
         Result := Endpoint_Closed;
         return;
      end if;

      Close_Endpoint (Item.Owner.all, Item.Endpoint, Result);
      if Result = Endpoint_Closed or else Result = Stale_Endpoint then
         Item.Endpoint := Endpoints.No_Endpoint;
      end if;
   end Close;

   overriding procedure Finalize (Item : in out Endpoint_Handle) is
      Ignored : Close_Result;
   begin
      Close (Item, Ignored);
   end Finalize;

   function Is_Current (Item : Node; Endpoint : Endpoints.Endpoint_Reference) return Boolean is
     (Endpoints.Is_Valid (Endpoint)
      and then Endpoints.Destination_Node (Endpoint) = Item.Owner_Node
      and then Item.State.Is_Current (Endpoints.Slot (Endpoint), Endpoints.Generation (Endpoint)));

   function Current (Item : Node) return Node_Snapshot is
     (Item.State.Current);

end Flyology.Remoting.Nodes.In_Process;
