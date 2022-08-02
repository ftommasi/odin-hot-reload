package wave;
import "vendor:raylib"
import "core:strings"
import "core:encoding/json"
import "core:os"
import "core:fmt"
//TODO(Fausto): refactor entities to be SOA instead of AOS

//Structs

KeyboardState :: enum{
	IsKeyUp        ,
	IsKeyDown      ,
   IsKeyPressed ,
	IsKeyReleased  ,
}

NUM_ENTITIES :: 100
NUMKEYS      :: 336
State :: struct {
   paused       : bool,
   entities     : [NUM_ENTITIES]Entity, 
   num_ents     : u32,
   frameCounter : u32,
   keyboard_state : [NUMKEYS]KeyboardState, //NUMKEYS :: 336 => number of keyboard keys supported by raylib
};

Entity :: struct{
   pos  : raylib.Vector2,
   vel  : raylib.Vector2,
   acc  : raylib.Vector2,

   size : f32,
   valid : bool,
   color : raylib.Color
};

Request :: enum {
    None,
    Reload,
    Quit,
}


//Globals
ZERO_VEC :: raylib.Vector2{0.0, 0.0};
PLAYER_SIZE :: 10.0;
state_json_path :: "state.json"

@(export)
update_and_draw :: proc(cur_state : ^State) -> Request{
   req := update(cur_state);
   return req
}

@(export)
on_load :: proc(cur_state : ^State){
   json_data, ok := os.read_entire_file_from_filename(state_json_path)
   if !ok{
      fmt.println("on_load: Error reading State JSON. Marshaling..",ok);
      if state_bytes, err := json.marshal(cur_state^); err != json.Marshal_Data_Error.None {
        os.write_entire_file(state_json_path, state_bytes);
       }else{
         fmt.println("on_load: error marshalling and writing State json",err,state_bytes)
       }
   }
   if json.unmarshal_string(string(json_data),cur_state) != nil{
        fmt.println("on_load: error unmarshalling State json", string(json_data));
   }
}
@(export)
on_unload :: proc(cur_state : ^State){
   if state_bytes, err := json.marshal(cur_state^); err != json.Marshal_Data_Error.None {
        os.write_entire_file(state_json_path, state_bytes);
   }else{
      fmt.println("on_unload: error marshalling and writing State json",err)
   }
}


add_entity :: proc(cur_state : ^State) -> Entity{
   //TODO(How do we want to handle this)  
   new_ent := Entity{
      ZERO_VEC,
      ZERO_VEC,
      ZERO_VEC,
      PLAYER_SIZE,
      true,
      raylib.RED
   };
   cur_state.entities[cur_state.num_ents] = new_ent;
   cur_state.num_ents += 1;
   return new_ent;
}

clamp_vector_f32 :: proc(vec : raylib.Vector2, clamp : f32) -> raylib.Vector2{
         ret_vec := vec;
         if ret_vec.x < clamp{
            ret_vec.x = 0;
         } 
         if ret_vec.y  < clamp {
            ret_vec.y = 0;
         }
   return ret_vec;
}

clamp_vector_v :: proc(vec : raylib.Vector2, clamp_vec : raylib.Vector2) -> raylib.Vector2{
         ret_vec := vec;
         if ret_vec.x < clamp_vec.x{
            ret_vec.x = 0;
         } 
         if ret_vec.y  < clamp_vec.y {
            ret_vec.y = 0;
         }
   return ret_vec;
}

clamp_vector :: proc{clamp_vector_f32,clamp_vector_v};

update :: proc(cur_state : ^State) -> Request{
  using raylib ;
   //TODO(Fausto): refactor entities to be SOA instead of AOS
   cur_request := Request.None;

  cur_state.entities[0].color = GREEN; 
   
   
   //Process player input
   if cur_state.keyboard_state[KeyboardKey.D] == .IsKeyDown {
         cur_state.entities[0].vel.x += 0.8;
         fmt.println("d")
   }

   if IsKeyDown(.A) {
         cur_state.entities[0].vel.x -= 0.8;
   }

   if IsKeyDown(.S) {
         cur_state.entities[0].vel.y += 0.8;
   }

   if IsKeyDown(.W) {
         cur_state.entities[0].vel.y -= 0.8;
   }

   if IsKeyDown(.F5){
      cur_request = .Reload
   }
   
   for entity,i in cur_state.entities{
      if entity.valid{
         cur_state.entities[i].vel -= 0.1;
         cur_state.entities[i].vel = clamp_vector(cur_state.entities[i].vel,0.1);
         cur_state.entities[i].pos += entity.vel;
      }
   }
   return cur_request;
}