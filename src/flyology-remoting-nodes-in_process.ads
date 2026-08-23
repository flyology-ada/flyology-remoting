with Flyology.Buffers;
with Flyology.Remoting.Endpoints;
with Flyology.Remoting.Identities;
with Flyology.Remoting.Transports.In_Process;
private with Ada.Finalization;

--  Supplies one bounded in-process remoting node. Endpoint references select
--  fixed-capacity mailboxes; payload ownership moves through the reference
--  transport without copying bytes.

generic
   Storage : not null access Flyology.Buffers.Pool;
   Endpoint_Capacity : Positive;
   Mailbox_Capacity : Positive;
   Maximum_Concurrent_Operations_Per_Endpoint : Positive;
package Flyology.Remoting.Nodes.In_Process is

   package Payload_Transport is new
     Flyology.Remoting.Transports.In_Process (Queue_Capacity => Mailbox_Capacity);

   subtype Writable_Payload is Payload_Transport.Writable_Payload (Storage);
   subtype Received_Payload is Payload_Transport.Received_Payload (Storage);

   type Node (<>) is limited private;
   type Endpoint_Handle (Owner : not null access Node) is limited private;

   --  Create an empty node for one exact process incarnation.
   function Create (Owner : Identities.Node_Reference) return Node;

   function Owner (Item : Node) return Identities.Node_Reference;

   --  Claim one scope-owned endpoint without waiting. Reuse advances a
   --  nonwrapping generation; exhausted slots never become current again.
   --  Finalization closes and drains a successfully claimed endpoint.
   function Claim (Item : not null access Node) return Endpoint_Handle;

   function Status (Item : Endpoint_Handle) return Claim_Result;

   function Has_Endpoint (Item : Endpoint_Handle) return Boolean;

   function Reference (Item : Endpoint_Handle) return Endpoints.Endpoint_Reference
   with Pre => Has_Endpoint (Item);

   --  Explicitly close a claimed endpoint. This is idempotent after success;
   --  finalization remains the cleanup fallback.
   procedure Close (Item : in out Endpoint_Handle; Result : out Close_Result);

   --  Attempt one ownership-transferring send to an exact local endpoint.
   procedure Try_Send
     (Item        : in out Node;
      Destination : Endpoints.Endpoint_Reference;
      Value       : in out Writable_Payload;
      Result      : out Try_Send_Result)
   with
     Pre  => Payload_Transport.Has_Payload (Value),
     Post => (Result = Message_Accepted) = (not Payload_Transport.Has_Payload (Value));

   --  Forward a received payload to another exact local endpoint.
   procedure Try_Send
     (Item        : in out Node;
      Destination : Endpoints.Endpoint_Reference;
      Value       : in out Received_Payload;
      Result      : out Try_Send_Result)
   with
     Pre  => Payload_Transport.Has_Payload (Value),
     Post => (Result = Message_Accepted) = (not Payload_Transport.Has_Payload (Value));

   --  Attempt to receive the oldest payload accepted for Endpoint.
   procedure Try_Receive
     (Item     : in out Node;
      Endpoint : Endpoints.Endpoint_Reference;
      Target   : in out Received_Payload;
      Result   : out Try_Receive_Result)
   with
     Pre  => not Payload_Transport.Has_Payload (Target),
     Post => (Result = Message_Received) = Payload_Transport.Has_Payload (Target);

   --  Report whether Endpoint is active and accepts new operations.
   function Is_Current (Item : Node; Endpoint : Endpoints.Endpoint_Reference) return Boolean;

   function Current (Item : Node) return Node_Snapshot;

private
   subtype Slot_Index is Positive range 1 .. Endpoint_Capacity;
   subtype Operation_Count is Natural range 0 .. Maximum_Concurrent_Operations_Per_Endpoint;

   type Boolean_Array is array (Slot_Index) of Boolean;
   type Generation_Array is array (Slot_Index) of Endpoints.Endpoint_Generation;
   type Operation_Count_Array is array (Slot_Index) of Operation_Count;

   type Pin_Result is (Pinned, Pin_Closing, Pin_Stale, Pin_Limit);
   type Begin_Close_Result is (Close_Begun, Close_Busy, Close_Stale);

   protected type Gate_State is
      procedure Try_Claim
        (Claimed_Slot       : out Endpoints.Endpoint_Slot;
         Claimed_Generation : out Endpoints.Endpoint_Generation;
         Result             : out Claim_Result);
      procedure Try_Pin
        (Slot       : Endpoints.Endpoint_Slot;
         Generation : Endpoints.Endpoint_Generation;
         Result     : out Pin_Result;
         Held       : out Boolean);
      procedure Unpin (Slot : Endpoints.Endpoint_Slot; Generation : Endpoints.Endpoint_Generation);
      procedure Begin_Close
        (Slot       : Endpoints.Endpoint_Slot;
         Generation : Endpoints.Endpoint_Generation;
         Result     : out Begin_Close_Result;
         Held       : out Boolean);
      procedure Abandon_Close
        (Slot : Endpoints.Endpoint_Slot; Generation : Endpoints.Endpoint_Generation);
      function Is_Quiescent
        (Slot : Endpoints.Endpoint_Slot; Generation : Endpoints.Endpoint_Generation) return Boolean;
      procedure Complete_Close
        (Slot : Endpoints.Endpoint_Slot; Generation : Endpoints.Endpoint_Generation);
      function Is_Current
        (Slot : Endpoints.Endpoint_Slot; Generation : Endpoints.Endpoint_Generation) return Boolean;
      function Current return Node_Snapshot;
   private
      Active       : Boolean_Array := (others => False);
      Closing      : Boolean_Array := (others => False);
      Close_Active : Boolean_Array := (others => False);
      Generations  : Generation_Array := (others => Endpoints.No_Endpoint_Generation);
      Pins         : Operation_Count_Array := (others => 0);
   end Gate_State;

   subtype Mailbox is Payload_Transport.Lane (Storage);
   type Mailbox_Array is array (Slot_Index) of Mailbox;

   type Node is limited record
      Owner_Node : Identities.Node_Reference;
      State      : aliased Gate_State;
      Mailboxes  : Mailbox_Array;
   end record;

   type Endpoint_Handle (Owner : not null access Node) is
     limited new Ada.Finalization.Limited_Controlled with
   record
      Endpoint : Endpoints.Endpoint_Reference := Endpoints.No_Endpoint;
      Outcome  : Claim_Result := Directory_Full;
   end record;

   overriding procedure Finalize (Item : in out Endpoint_Handle);

end Flyology.Remoting.Nodes.In_Process;
