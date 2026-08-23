package body Flyology.Remoting.Transports.In_Process is

   package Buffers renames Flyology.Buffers;
   package Channels renames Flyology.Buffers.Channels;

   procedure Acquire (Item : in out Writable_Payload) is
   begin
      Buffers.Acquire (Item.Buffer);
   end Acquire;

   procedure Try_Acquire (Item : in out Writable_Payload; Acquired : out Boolean) is
   begin
      Buffers.Try_Acquire (Item.Buffer, Acquired);
   end Try_Acquire;

   procedure Release (Item : in out Writable_Payload) is
   begin
      Buffers.Release (Item.Buffer);
   end Release;

   procedure Release (Item : in out Received_Payload) is
   begin
      Buffers.Release (Item.Buffer);
   end Release;

   function Has_Payload (Item : Writable_Payload) return Boolean is
     (Buffers.Has_Buffer (Item.Buffer));

   function Has_Payload (Item : Received_Payload) return Boolean is
     (Buffers.Has_Buffer (Item.Buffer));

   function Length (Item : Writable_Payload) return Natural is
     (Buffers.Length (Item.Buffer));

   function Length (Item : Received_Payload) return Natural is
     (Buffers.Length (Item.Buffer));

   function Payload_Capacity (Item : Writable_Payload) return Positive is
     (Buffers.Buffer_Capacity (Item.Buffer));

   procedure With_Writable_Data
     (Item    : in out Writable_Payload;
      Process :
        not null access procedure (Data : in out Ada.Streams.Stream_Element_Array; Length : in out Natural))
   is
   begin
      Buffers.With_Writable_Data (Item.Buffer, Process);
   end With_Writable_Data;

   procedure With_Readable_Data
     (Item : Writable_Payload; Process : not null access procedure (Data : Ada.Streams.Stream_Element_Array))
   is
   begin
      Buffers.With_Readable_Data (Item.Buffer, Process);
   end With_Readable_Data;

   procedure With_Readable_Data
     (Item : Received_Payload; Process : not null access procedure (Data : Ada.Streams.Stream_Element_Array))
   is
   begin
      Buffers.With_Readable_Data (Item.Buffer, Process);
   end With_Readable_Data;

   procedure Copy_From (Item : in out Writable_Payload; Data : Ada.Streams.Stream_Element_Array) is
   begin
      Buffers.Copy_From (Item.Buffer, Data);
   end Copy_From;

   procedure Try_Send
     (Item : in out Lane; Value : in out Writable_Payload; Result : out Try_Send_Result)
   is
      Channel_Result : Channels.Try_Send_Result;
   begin
      Channels.Try_Send_Move (Item.Queue, Value.Buffer, Channel_Result);
      case Channel_Result is
         when Channels.Item_Sent =>
            Result := Message_Accepted;
         when Channels.Channel_Full =>
            Result := Backpressure;
         when Channels.Send_Closed =>
            Result := Send_Closed;
      end case;
   end Try_Send;

   procedure Try_Send
     (Item : in out Lane; Value : in out Received_Payload; Result : out Try_Send_Result)
   is
      Channel_Result : Channels.Try_Send_Result;
   begin
      Channels.Try_Send_Move (Item.Queue, Value.Buffer, Channel_Result);
      case Channel_Result is
         when Channels.Item_Sent =>
            Result := Message_Accepted;
         when Channels.Channel_Full =>
            Result := Backpressure;
         when Channels.Send_Closed =>
            Result := Send_Closed;
      end case;
   end Try_Send;

   procedure Try_Receive
     (Item : in out Lane; Target : in out Received_Payload; Result : out Try_Receive_Result)
   is
      Channel_Result : Channels.Try_Receive_Result;
   begin
      Channels.Try_Receive_Move (Item.Queue, Target.Buffer, Channel_Result);
      case Channel_Result is
         when Channels.Item_Received =>
            Result := Message_Received;
         when Channels.Channel_Empty =>
            Result := No_Message;
         when Channels.Receive_Closed =>
            Result := Receive_Closed;
      end case;
   end Try_Receive;

   procedure Close (Item : in out Lane) is
   begin
      Channels.Close (Item.Queue);
   end Close;

   function Current (Item : Lane) return Lane_Snapshot is
      State : constant Channels.Snapshot := Channels.Current (Item.Queue);
   begin
      return (Closed => State.Closed, Pending => State.Pending);
   end Current;

end Flyology.Remoting.Transports.In_Process;
