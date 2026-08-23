package body Flyology.Remoting.Messages is

   use type Flyology_Wire.Octet;

   function Message_ID_From_Bytes (Value : Message_ID_Bytes) return Message_ID is
     (Message_ID (Value));

   function To_Bytes (Value : Message_ID) return Message_ID_Bytes is
     (Message_ID_Bytes (Value));

   function Is_Valid (Value : Message_ID) return Boolean is
   begin
      for Octet of Value loop
         if Octet /= 0 then
            return True;
         end if;
      end loop;

      return False;
   end Is_Valid;

end Flyology.Remoting.Messages;
