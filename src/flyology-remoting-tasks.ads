with Flyology.Remoting.Identities;
with Interfaces;

--  Defines transport-neutral, exact-generation remote-task references and
--  bounded lifecycle observations. These values contain no Ada Task_Id,
--  supervisor address, transport object, or access value.

package Flyology.Remoting.Tasks
  with Preelaborate
is

   subtype Task_Word is Interfaces.Unsigned_64;

   --  Stable logical-task identity within one node incarnation. Zero is
   --  invalid. A supervised restart retains this identity.
   type Task_ID is private;

   --  Nonwrapping generation of one logical task. Zero is invalid.
   type Task_Generation is private;

   No_Task_ID         : constant Task_ID;
   No_Task_Generation : constant Task_Generation;

   function Task_ID_From_Word (Value : Task_Word) return Task_ID;
   function Generation_From_Word (Value : Task_Word) return Task_Generation;
   function To_Word (Value : Task_ID) return Task_Word;
   function To_Word (Value : Task_Generation) return Task_Word;
   function Is_Valid (Value : Task_ID) return Boolean;
   function Is_Valid (Value : Task_Generation) return Boolean;

   --  One exact logical task generation in one exact node incarnation.
   type Task_Reference is private;
   No_Task : constant Task_Reference;

   function Make_Task_Reference
     (Node       : Identities.Node_Reference;
      Identity   : Task_ID;
      Generation : Task_Generation) return Task_Reference;
   function Is_Valid (Value : Task_Reference) return Boolean;
   function Destination_Node (Value : Task_Reference) return Identities.Node_Reference;
   function Identity (Value : Task_Reference) return Task_ID;
   function Generation (Value : Task_Reference) return Task_Generation;

   --  Portable classification copied from destination supervision. It omits
   --  process-local Ada exception and task identities.
   type Completion_Kind is
     (Unknown_Completion,
      Normal_Return,
      Unhandled_Exception,
      Cancelled,
      Supervisor_Shutdown,
      Abnormal_Completion,
      Activation_Failure,
      Readiness_Timeout,
      Restart_Requested,
      Unhealthy,
      Stop_Timeout,
      Stuck,
      Policy_Exhaustion);

   Maximum_Exception_Name_Length : constant := 96;
   Maximum_Diagnostic_Length     : constant := 512;

   subtype Exception_Name_Length is Natural range 0 .. Maximum_Exception_Name_Length;
   subtype Diagnostic_Length is Natural range 0 .. Maximum_Diagnostic_Length;

   type Completion_Summary is record
      Kind                     : Completion_Kind := Unknown_Completion;
      Exception_Name_Length    : Tasks.Exception_Name_Length := 0;
      Exception_Name_Truncated : Boolean := False;
      Exception_Name           : String (1 .. Maximum_Exception_Name_Length) := (others => ' ');
      Message_Length           : Diagnostic_Length := 0;
      Message_Truncated        : Boolean := False;
      Message                  : String (1 .. Maximum_Diagnostic_Length) := (others => ' ');
   end record;

   function Exception_Name_Text (Item : Completion_Summary) return String
   is (Item.Exception_Name (1 .. Item.Exception_Name_Length));

   function Message_Text (Item : Completion_Summary) return String
   is (Item.Message (1 .. Item.Message_Length));

   --  Result of observing one exact remote task generation.
   --
   --  Peer_Unreachable means only that the selected live session cannot
   --  currently make progress. Node_Incarnation_Ended requires an
   --  authoritative process-liveness source; a socket disconnect is not
   --  sufficient. Task_Replaced never follows the replacement implicitly.
   type Observation_Status is
     (Observation_Timed_Out,
      Task_Ended,
      Task_Replaced,
      Node_Incarnation_Ended,
      Peer_Unreachable);

   type Task_Observation (Status : Observation_Status := Observation_Timed_Out) is record
      case Status is
         when Task_Ended =>
            Completion : Completion_Summary;
         when Task_Replaced =>
            Replacement : Task_Reference;
         when Observation_Timed_Out | Node_Incarnation_Ended | Peer_Unreachable =>
            null;
      end case;
   end record;

private
   type Task_ID is new Task_Word;
   type Task_Generation is new Task_Word;

   No_Task_ID         : constant Task_ID := 0;
   No_Task_Generation : constant Task_Generation := 0;

   type Task_Reference is record
      Node       : Identities.Node_Reference := Identities.No_Node;
      Identity   : Task_ID := No_Task_ID;
      Generation : Task_Generation := No_Task_Generation;
   end record;

   No_Task : constant Task_Reference := (others => <>);

end Flyology.Remoting.Tasks;
