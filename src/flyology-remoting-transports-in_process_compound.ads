private with Ada.Finalization;
with Ada.Streams;
with Flyology.Buffers;
private with Flyology.Buffers.Channels;
private with Flyology.Buffers.Drivers;
with Flyology.Remoting.Protocol.V1.Headers;

--  Supplies a bounded in-process compound-message transport. Each accepted
--  queue entry owns separate canonical header and opaque payload buffer
--  leases. The payload bytes are never copied during send, receive, or
--  forwarding.

generic
   Queue_Capacity              : Positive;
   Maximum_Concurrent_Builders : Positive;
package Flyology.Remoting.Transports.In_Process_Compound is

   package Headers renames Flyology.Remoting.Protocol.V1.Headers;

   --  Raised while elaborating a lane whose header blocks cannot retain one
   --  canonical V1 header or whose pool cannot cover the queue and builders.
   Invalid_Configuration : exception;

   --  Immediate compound-send outcome. Invalid value checks precede the
   --  closed fence, builder/header exhaustion, and queue admission.
   type Try_Send_Result is
     (Invalid_Header,
      Payload_Length_Mismatch,
      Local_Resource_Exhausted,
      Backpressure,
      Send_Closed,
      Message_Accepted);

   --  Immediate compound-receive outcome.
   type Try_Receive_Result is (Message_Received, No_Message, Receive_Closed);

   --  One FIFO acceptance path. Both pools must outlive the lane, every
   --  builder for it, and every message received from it.
   type Lane
     (Payload_Storage : not null access Flyology.Buffers.Pool;
      Header_Storage  : not null access Flyology.Buffers.Pool)
   is limited private;

   --  Noncopyable precommit owner of one builder reservation and one sealed
   --  canonical header lease.
   type Message_Builder (Owner : not null access Lane) is limited private;

   --  Result of attempting to reserve and seal one header builder.
   type Prepare_Result is
     (Builder_Prepared, Prepare_Invalid_Header, Prepare_Local_Resource_Exhausted, Prepare_Closed);

   --  Caller-owned mutable payload. Acceptance leaves it vacant.
   type Writable_Payload (Storage : not null access Flyology.Buffers.Pool) is limited private;

   --  Receiver-owned immutable compound value. It owns both the canonical
   --  header lease and the unchanged payload lease.
   type Received_Message
     (Payload_Storage : not null access Flyology.Buffers.Pool;
      Header_Storage  : not null access Flyology.Buffers.Pool)
   is limited private;

   --  Reserve one bounded builder and seal Envelope into a canonical header
   --  buffer. Item retains its reservation and header until one commit
   --  attempt, Reset, or finalization. Every commit outcome consumes Item.
   procedure Prepare
     (Item : in out Message_Builder; Envelope : Headers.Header; Result : out Prepare_Result)
   with Pre => not Is_Prepared (Item), Post => (Result = Builder_Prepared) = Is_Prepared (Item);

   --  Report whether Item owns both a builder reservation and sealed header.
   function Is_Prepared (Item : Message_Builder) return Boolean;

   --  Release a prepared builder. Resetting an empty builder is harmless.
   procedure Reset (Item : in out Message_Builder)
   with Post => not Is_Prepared (Item);

   --  Wait for one payload slot and attach it to vacant Item.
   procedure Acquire (Item : in out Writable_Payload)
   with Pre => not Has_Payload (Item), Post => Has_Payload (Item) and then Length (Item) = 0;

   --  Attempt to acquire one payload slot without waiting.
   procedure Try_Acquire (Item : in out Writable_Payload; Acquired : out Boolean)
   with Pre => not Has_Payload (Item), Post => Acquired = Has_Payload (Item);

   --  Release writable payload ownership if present.
   procedure Release (Item : in out Writable_Payload)
   with Post => not Has_Payload (Item);

   --  Report whether Item owns neither segment. This is the exact receive
   --  target predicate; a partially occupied value is not vacant.
   function Is_Vacant (Item : Received_Message) return Boolean;

   --  Release both received message segments if present.
   procedure Release (Item : in out Received_Message)
   with Post => Is_Vacant (Item);

   --  Report whether Item owns a writable payload lease.
   function Has_Payload (Item : Writable_Payload) return Boolean;

   --  Report whether Item owns both leases and a validated semantic header.
   function Has_Message (Item : Received_Message) return Boolean;

   --  Return the initialized writable payload length, or zero when vacant.
   function Length (Item : Writable_Payload) return Natural;

   --  Return the received payload length, or zero when vacant.
   function Length (Item : Received_Message) return Natural;

   --  Return the fixed writable payload capacity.
   function Payload_Capacity (Item : Writable_Payload) return Positive;

   --  Return the validated semantic header retained with Item.
   function Envelope (Item : Received_Message) return Headers.Header
   with Pre => Has_Message (Item);

   --  Borrow the writable payload block for one synchronous callback.
   procedure With_Writable_Data
     (Item    : in out Writable_Payload;
      Process :
        not null access procedure (Data : in out Ada.Streams.Stream_Element_Array; Length : in out Natural))
   with Pre => Has_Payload (Item);

   --  Borrow initialized sender-owned bytes for one synchronous callback.
   --  Process must not retain a derived address or reference.
   procedure With_Readable_Data
     (Item : Writable_Payload; Process : not null access procedure (Data : Ada.Streams.Stream_Element_Array))
   with Pre => Has_Payload (Item);

   --  Borrow immutable received payload bytes for one synchronous callback.
   --  Process must not retain a derived address or reference.
   procedure With_Readable_Data
     (Item : Received_Message; Process : not null access procedure (Data : Ada.Streams.Stream_Element_Array))
   with Pre => Has_Message (Item);

   --  Borrow the exact canonical received header bytes for one synchronous
   --  callback. Process must not retain a derived address or reference.
   procedure With_Encoded_Header
     (Item : Received_Message; Process : not null access procedure (Data : Ada.Streams.Stream_Element_Array))
   with Pre => Has_Message (Item);

   --  Copy bytes into a writable payload convenience boundary.
   procedure Copy_From (Item : in out Writable_Payload; Data : Ada.Streams.Stream_Element_Array)
   with
     Pre  => Has_Payload (Item) and then Data'Length <= Payload_Capacity (Item),
     Post => Length (Item) = Data'Length;

   --  Validation precedes local builder/header acquisition, which precedes
   --  bounded queue admission. Only Message_Accepted transfers Value.
   procedure Try_Send
     (Item     : in out Lane;
      Envelope : Headers.Header;
      Value    : in out Writable_Payload;
      Result   : out Try_Send_Result)
   with
     Pre  => Has_Payload (Value) and then Value.Storage = Item.Payload_Storage,
     Post => (Result = Message_Accepted) = (not Has_Payload (Value));

   --  Attempt admission using an already sealed header. Every result consumes
   --  the builder. Rejection preserves the payload but releases the header.
   procedure Try_Commit
     (Item : in out Message_Builder; Value : in out Writable_Payload; Result : out Try_Send_Result)
   with
     Pre  =>
       Is_Prepared (Item)
       and then Has_Payload (Value)
       and then Value.Storage = Item.Owner.Payload_Storage,
     Post =>
       not Is_Prepared (Item)
       and then (Result = Message_Accepted) = (not Has_Payload (Value));

   --  Re-envelope and forward one received payload without copying it. A
   --  rejected forward preserves both of Value's original segments.
   procedure Try_Forward
     (Item     : in out Lane;
      Envelope : Headers.Header;
      Value    : in out Received_Message;
      Result   : out Try_Send_Result)
   with
     Pre  =>
       Has_Message (Value)
       and then Value.Payload_Storage = Item.Payload_Storage,
     Post =>
       (if Result = Message_Accepted then Is_Vacant (Value) else Has_Message (Value));

   --  Forward using an already sealed replacement header. Every result
   --  consumes the builder; rejection preserves both original message leases.
   procedure Try_Commit_Forward
     (Item : in out Message_Builder; Value : in out Received_Message; Result : out Try_Send_Result)
   with
     Pre  =>
       Is_Prepared (Item)
       and then Has_Message (Value)
       and then Value.Payload_Storage = Item.Owner.Payload_Storage,
     Post =>
       not Is_Prepared (Item)
       and then (if Result = Message_Accepted then Is_Vacant (Value) else Has_Message (Value));

   --  Attempt to receive the oldest accepted pair. No_Message and
   --  Receive_Closed preserve a vacant Target.
   procedure Try_Receive
     (Item   : in out Lane;
      Target : in out Received_Message;
      Result : out Try_Receive_Result)
   with
     Pre  =>
       Is_Vacant (Target)
       and then Target.Payload_Storage = Item.Payload_Storage
       and then Target.Header_Storage = Item.Header_Storage,
     Post =>
       (if Result = Message_Received then Has_Message (Target) else Is_Vacant (Target));

   --  Fence new builders and sends while retaining accepted pairs for drain.
   procedure Close (Item : in out Lane);

   --  Return the private payload queue's coherent close and pending state.
   function Current (Item : Lane) return Lane_Snapshot;

private
   package Channels renames Flyology.Buffers.Channels;
   --  The definite detached-buffer SPI is the bounded provider storage for
   --  header tokens whose pool is selected by each Lane at run time.
   package Drivers renames Flyology.Buffers.Drivers;

   subtype Header_Slot is Positive range 1 .. Queue_Capacity;
   type Header_Slot_Array is array (Header_Slot) of Natural;
   type Boolean_Array is array (Header_Slot) of Boolean;
   type Header_Array is array (Header_Slot) of Headers.Header;
   type Detached_Header_Array is array (Header_Slot) of Drivers.Detached_Buffer;

   type Builder_Ticket is limited record
      Held : Boolean := False;
   end record;

   type Build_Start_Result is (Build_Started, Build_Limit, Build_Closed);

   protected type Received_Release_Gate is
      procedure Release
        (Payload : in out Flyology.Buffers.Unique_Buffer;
         Header  : in out Flyology.Buffers.Unique_Buffer);
   end Received_Release_Gate;

   type Writable_Payload (Storage : not null access Flyology.Buffers.Pool) is limited record
      Buffer : Flyology.Buffers.Unique_Buffer (Storage);
   end record;

   type Received_Message
     (Payload_Storage : not null access Flyology.Buffers.Pool;
      Header_Storage  : not null access Flyology.Buffers.Pool)
   is limited record
      Payload_Buffer : Flyology.Buffers.Unique_Buffer (Payload_Storage);
      Header_Buffer  : Flyology.Buffers.Unique_Buffer (Header_Storage);
      Header_Value   : Headers.Header := Headers.No_Header;
      Release_Gate   : Received_Release_Gate;
   end record;

   protected type Compound_State is
      procedure Try_Begin_Build
        (Queue : Channels.Channel; Ticket : in out Builder_Ticket; Result : out Build_Start_Result);
      procedure Abandon_Build (Ticket : in out Builder_Ticket);
      procedure Reset_Build (Header : in out Drivers.Detached_Buffer; Ticket : in out Builder_Ticket);
      procedure Allocate_Header_Slot (Slot : out Header_Slot);
      procedure Release_Header_Slot (Slot : Header_Slot);
      procedure Finish_Build (Ticket : in out Builder_Ticket);
      procedure Try_Commit
        (Queue   : in out Channels.Channel;
         Header  : in out Drivers.Detached_Buffer;
         Payload : in out Flyology.Buffers.Unique_Buffer;
         Value   : Headers.Header;
         Ticket  : in out Builder_Ticket;
         Result  : out Try_Send_Result);
      procedure Try_Commit_Forward
        (Queue  : in out Channels.Channel;
         Header : in out Drivers.Detached_Buffer;
         Value  : in out Received_Message;
         New_Header : Headers.Header;
         Ticket : in out Builder_Ticket;
         Result : out Try_Send_Result);
      procedure Try_Receive
        (Queue : in out Channels.Channel; Target : in out Received_Message; Result : out Try_Receive_Result);
      procedure Close (Queue : in out Channels.Channel);
      function Current (Queue : Channels.Channel) return Lane_Snapshot;
   private
      Header_Leases  : Detached_Header_Array;
      Header_Values  : Header_Array := (others => Headers.No_Header);
      Active         : Boolean_Array := (others => False);
      Free_Slots     : Header_Slot_Array := (others => 0);
      Free_Count     : Natural := 0;
      Next_Unused    : Natural := Header_Slot'First;
      Active_Builders : Natural := 0;
      Stopped         : Boolean := False;
   end Compound_State;

   type Lane
     (Payload_Storage : not null access Flyology.Buffers.Pool;
      Header_Storage  : not null access Flyology.Buffers.Pool)
   is limited new Ada.Finalization.Limited_Controlled with record
      Queue : Channels.Channel (Payload_Storage, Capacity => Queue_Capacity);
      State : aliased Compound_State;
   end record;

   overriding procedure Initialize (Item : in out Lane);

   overriding procedure Finalize (Item : in out Lane);

   type Message_Builder (Owner : not null access Lane) is
     limited new Ada.Finalization.Limited_Controlled with
   record
      Header_Lease : Drivers.Detached_Buffer;
      Header_Value : Headers.Header := Headers.No_Header;
      Ticket       : Builder_Ticket;
   end record;

   overriding procedure Finalize (Item : in out Message_Builder);

   type Prepare_Guard (Builder : not null access Message_Builder) is
     limited new Ada.Finalization.Limited_Controlled with
   record
      Armed : Boolean := True;
   end record;

   procedure Disarm (Item : in out Prepare_Guard);

   overriding procedure Finalize (Item : in out Prepare_Guard);

end Flyology.Remoting.Transports.In_Process_Compound;
