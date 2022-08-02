package wave

import "vendor:raylib"
import "core:strings"
import "core:encoding/json"
import "core:os"
import "core:fmt"

init :: proc(){
    screenWidth  : i32 = 800;
    screenHeight : i32 = 450;
    raylib.InitWindow(screenWidth, screenHeight, "wave");
    raylib.SetTargetFPS(60);
    cur_state.entities[0] = {
      {(f32)(screenWidth/2),(f32)(screenHeight/2)},
         ZERO_VEC,
         ZERO_VEC,
         PLAYER_SIZE,
         true,
         raylib.BLUE
      }; // init player entity
}

deinit :: proc(){
   raylib.CloseWindow();
}

draw :: proc(){
   using raylib;
   BeginDrawing();
   defer EndDrawing();

   ClearBackground(BLACK);
   DrawText("MARK",400,225,10,WHITE)
   DrawRectangleV(cur_state.entities[0].pos,{PLAYER_SIZE,PLAYER_SIZE},BLUE);
}

cur_state : State;
main :: proc() {
   init();
   defer deinit();

   plugin: Plugin;
   if !plugin_load(&plugin, "ve.dll",&cur_state) {
       fmt.println("error loading ve.dll");
       return;
   }
   defer plugin_unload(&plugin,&cur_state);
   //reloader := start_reload_thread("cmd.exe /c build.bat", "."); //Watch current directory and set build.bat as recompile script

   //compile_game_dll(); //Note(for convenience we compile the DLL immediatel before the main loop starts)

   for  !raylib.WindowShouldClose(){
      /*
      Process user input listener in host app. Do logic in game app
       */
      if raylib.IsKeyDown(raylib.KeyboardKey.D) {
         cur_state.keyboard_state[raylib.KeyboardKey.D] = KeyboardState.IsKeyDown
      }
      else{
         cur_state.keyboard_state[raylib.KeyboardKey.D] = KeyboardState.IsKeyUp
      }

      plugin.update_and_draw_proc(&cur_state)
      draw()
   } 
   plugin.on_unload_proc(&cur_state)
}