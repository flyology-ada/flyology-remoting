private with Ada.Finalization;
with Ada.Streams;
with Flyology.Buffers;
with Flyology.Remoting.Endpoints;
with Flyology.Remoting.Messages;
private with Flyology.Remoting.Protocol.V1.Headers;
with Flyology.Remoting.Transports;
private with Flyology.Remoting.Transports.In_Process_Compound;
with Flyology_Wire;
with Flyology_Wire.Identities;

--  Supplies the immediate bounded outbound-admission boundary for one exact
--  in-process session binding. It does not perform endpoint delivery.
generic
   Queue_Capacity              : Positive;
   Maximum_Concurrent_Builders : Positive;
package Flyology.Remoting.Sessions.In_Process is

   --  Raised by Create when Header_Storage cannot hold one canonical V1
   --  header per accepted entry plus every concurrent precommit builder.
   Invalid_Configuration : exception;

   type Session (<>) is limited private;

   --  Create one immutable exact-binding outbound ingress. Both pools must
   --  outlive the session and every payload or message derived from them.
   --  Header_Storage must be dedicated to this live session, have blocks at
   --  least Protocol.V1.Headers.Encoded_Length bytes long, and have capacity
   --  for Queue_Capacity + Maximum_Concurrent_Builders leases.
   function Create
     (Bound           : Sessions.Binding;
      Payload_Storage : not null access Flyology.Buffers.Pool;
      Header_Storage  : not null access Flyology.Buffers.Pool) return Session;

   --  Return the exact binding retained by Item.
   function Session_Binding (Item : Session) return Sessions.Binding;

   type Writable_Payload (Storage : not null access Flyology.Buffers.Pool) is limited private;

   --  One transport-owned outbound descriptor dequeued from a session. It
   --  retains the exact binding by value with both immutable byte leases.
   type Accepted_Message
     (Payload_Storage : not null access Flyology.Buffers.Pool;
      Header_Storage  : not null access Flyology.Buffers.Pool)
   is limited private;

   procedure Acquire (Item : in out Writable_Payload)
   with Pre => not Has_Payload (Item), Post => Has_Payload (Item) and then Length (Item) = 0;

   procedure Try_Acquire (Item : in out Writable_Payload; Acquired : out Boolean)
   with Pre => not Has_Payload (Item), Post => Acquired = Has_Payload (Item);

   procedure Release (Item : in out Writable_Payload)
   with Post => not Has_Payload (Item);

   procedure Release (Item : in out Accepted_Message)
   with Post => Is_Vacant (Item);

   function Has_Payload (Item : Writable_Payload) return Boolean;

   function Has_Message (Item : Accepted_Message) return Boolean;

   function Is_Vacant (Item : Accepted_Message) return Boolean;

   function Length (Item : Writable_Payload) return Natural;

   function Length (Item : Accepted_Message) return Natural;

   function Payload_Capacity (Item : Writable_Payload) return Positive;

   procedure With_Writable_Data
     (Item    : in out Writable_Payload;
      Process :
        not null access procedure (Data : in out Ada.Streams.Stream_Element_Array; Length : in out Natural))
   with Pre => Has_Payload (Item);

   procedure With_Readable_Data
     (Item : Writable_Payload; Process : not null access procedure (Data : Ada.Streams.Stream_Element_Array))
   with Pre => Has_Payload (Item);

   procedure With_Readable_Data
     (Item : Accepted_Message; Process : not null access procedure (Data : Ada.Streams.Stream_Element_Array))
   with Pre => Has_Message (Item);

   procedure With_Encoded_Header
     (Item : Accepted_Message; Process : not null access procedure (Data : Ada.Streams.Stream_Element_Array))
   with Pre => Has_Message (Item);

   procedure Copy_From (Item : in out Writable_Payload; Data : Ada.Streams.Stream_Element_Array)
   with
     Pre  => Has_Payload (Item) and then Data'Length <= Payload_Capacity (Item),
     Post => Length (Item) = Data'Length;

   type Try_Send_Result is
     (Invalid_Message_Context,
      Invalid_Outbound_Route,
      Local_Resource_Exhausted,
      Backpressure,
      Session_Closed,
      Message_Accepted);

   --  Validate the complete route against Item's exact outbound binding,
   --  construct the relative V1 header, and attempt the first bounded session
   --  admission. Only Message_Accepted transfers Payload. Payload must belong
   --  to Item's payload pool; a mismatch raises Program_Error before status
   --  classification.
   procedure Try_Send
     (Item        : in out Session;
      Source      : Endpoints.Endpoint_Reference;
      Destination : Endpoints.Endpoint_Reference;
      Message     : Messages.Message_ID;
      Correlation : Messages.Message_ID;
      Writer      : Flyology_Wire.Identities.Schema_Identity;
      Payload     : in out Writable_Payload;
      Result      : out Try_Send_Result)
   with
     Pre  => Has_Payload (Payload),
     Post => (Result = Message_Accepted) = (not Has_Payload (Payload));

   --  Re-envelope an already dequeued message for another exact outbound
   --  binding without copying or mutably borrowing its payload. Payload must
   --  belong to Item's payload pool; a mismatch raises Program_Error before
   --  status classification.
   procedure Try_Forward
     (Item        : in out Session;
      Source      : Endpoints.Endpoint_Reference;
      Destination : Endpoints.Endpoint_Reference;
      Message     : Messages.Message_ID;
      Correlation : Messages.Message_ID;
      Writer      : Flyology_Wire.Identities.Schema_Identity;
      Payload     : in out Accepted_Message;
      Result      : out Try_Send_Result)
   with
     Pre  => Has_Message (Payload),
     Post => (if Result = Message_Accepted then Is_Vacant (Payload) else Has_Message (Payload));

   type Try_Take_Result is (Accepted_Message_Taken, No_Accepted_Message, Ingress_Drained);

   --  Dequeue one outbound descriptor for a transport driver. The exact
   --  binding is published into Target in the same abort-deferred action as
   --  the two leases. Target must use both of Item's pools; a mismatch raises
   --  Program_Error.
   procedure Try_Take_Accepted
     (Item   : in out Session;
      Target : in out Accepted_Message;
      Result : out Try_Take_Result)
   with
     Pre  => Is_Vacant (Target),
     Post => (if Result = Accepted_Message_Taken then Has_Message (Target) else Is_Vacant (Target));

   function Session_Binding (Item : Accepted_Message) return Sessions.Binding
   with Pre => Has_Message (Item);

   function Message (Item : Accepted_Message) return Messages.Message_ID
   with Pre => Has_Message (Item);

   function Correlation (Item : Accepted_Message) return Messages.Message_ID
   with Pre => Has_Message (Item);

   function Writer
     (Item : Accepted_Message) return Flyology_Wire.Identities.Schema_Identity
   with Pre => Has_Message (Item);

   --  Reconstruct complete outbound endpoint references from the retained
   --  binding and relative header fields.
   function Source (Item : Accepted_Message) return Endpoints.Endpoint_Reference
   with Pre => Has_Message (Item);

   function Destination (Item : Accepted_Message) return Endpoints.Endpoint_Reference
   with Pre => Has_Message (Item);

   --  Fence admission and synchronously release all descriptors still queued
   --  in Item. Already dequeued Accepted_Message values remain caller-owned.
   procedure Close (Item : in out Session);

   function Current (Item : Session) return Transports.Lane_Snapshot;

private
   package Headers renames Flyology.Remoting.Protocol.V1.Headers;

   package Compound is new
     Flyology.Remoting.Transports.In_Process_Compound
       (Queue_Capacity              => Queue_Capacity,
        Maximum_Concurrent_Builders => Maximum_Concurrent_Builders);

   type Writable_Payload (Storage : not null access Flyology.Buffers.Pool) is limited record
      Value : Compound.Writable_Payload (Storage);
   end record;

   protected type Received_Release_Gate is
      procedure Release
        (Value : in out Compound.Received_Message;
         Bound : in out Sessions.Binding);
   end Received_Release_Gate;

   type Accepted_Message
     (Payload_Storage : not null access Flyology.Buffers.Pool;
      Header_Storage  : not null access Flyology.Buffers.Pool)
   is limited record
      Value         : Compound.Received_Message (Payload_Storage, Header_Storage);
      Bound         : Sessions.Binding := Sessions.No_Binding;
      Release_Gate  : Received_Release_Gate;
   end record;

   protected type Session_Gate is
      procedure Try_Receive
        (Lane   : in out Compound.Lane;
         Bound  : Sessions.Binding;
         Target : in out Accepted_Message;
         Result : out Try_Take_Result);
      procedure Try_Forward
        (Lane     : in out Compound.Lane;
         Header   : Headers.Header;
         Payload  : in out Accepted_Message;
         Result   : out Try_Send_Result);
      procedure Close_And_Drain (Lane : in out Compound.Lane);
   end Session_Gate;

   type Session
     (Payload_Storage : not null access Flyology.Buffers.Pool;
      Header_Storage  : not null access Flyology.Buffers.Pool)
   is limited new Ada.Finalization.Limited_Controlled with record
      Bound   : Sessions.Binding := Sessions.No_Binding;
      Ingress : Compound.Lane (Payload_Storage, Header_Storage);
      Gate    : Session_Gate;
   end record;

   overriding procedure Finalize (Item : in out Session);

end Flyology.Remoting.Sessions.In_Process;
