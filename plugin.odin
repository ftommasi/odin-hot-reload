package wave

import "core:os"
import "core:fmt"
import "core:strings"
import "core:thread"

import win32 "core:sys/windows"
import lib "core:dynlib"


    _copy_file :: proc(src, dest : string, force := false) -> bool {
        ok : bool;
        file_data :[]byte;
        file_data,ok = os.read_entire_file_from_filename(src);
        if !ok do return false
        ok = os.write_entire_file(dest,file_data)
        return ok;
    }


get_file_time :: proc(filename: string) -> (bool, os.File_Time) {
    fd, err := os.open(filename);
    if err != os.ERROR_NONE do return false, 0;
    defer os.close(fd);

    file_time, err2 := os.last_write_time(fd);
    if err2 != os.ERROR_NONE do return false, 0;

    return true, file_time;
}

On_Load_Proc :: #type proc(^State);
On_Unload_Proc :: #type proc(^State);
Update_And_Draw_Proc :: #type proc(^State) -> Request;

Plugin :: struct {
    name: string,
    path_on_disk: string,
    module: lib.Library,
    last_write_time: os.File_Time,

    on_load_proc: On_Load_Proc,
    on_unload_proc: On_Unload_Proc,
    update_and_draw_proc: Update_And_Draw_Proc,
}

plugin_load :: proc(plugin: ^Plugin, name: string,cur_state : ^State) -> bool {
    temp_path :: "temp.dll";
    temp_pdb_path :: "temp.pdb";

    // copy dll to temp location
    if !_copy_file(name, temp_path, true) {
        fmt.println("ERR IN COPY FILE");
        fmt.eprintln("could not copy", name, "to", temp_path);
        return false;
    }

    //if !copy_file("bin/game.pdb", temp_pdb_path, true) {
    //    fmt.println("ERROR: cannot copy pdb from bin/game.pdb to bin/temp/temp.pdb");
    //}

    // load dll
    new_dll, ok := lib.load_library(temp_path);
    if !ok {
        fmt.println("ERR IN LOAD_LIBRARY");
        fmt.eprintln("could not load library", name);
        return false;
    }

    // load functions
   proc_address : rawptr;

   proc_address,ok = lib.symbol_address(new_dll, "on_load");
   on_load_proc : On_Load_Proc = cast(On_Load_Proc)proc_address
   if !ok {
      fmt.eprintln("error: could not load on_load proc");
      return false;
   } 
   
   proc_address, ok = lib.symbol_address(new_dll, "on_unload");
   on_unload_proc : On_Unload_Proc = cast(On_Unload_Proc) proc_address
   if !ok{
      fmt.eprintln("error: could not load on_unload proc");
      return false;
   } 

   proc_address,ok = lib.symbol_address(new_dll, "update_and_draw");
   update_and_draw_proc : Update_And_Draw_Proc = cast(Update_And_Draw_Proc)proc_address
   if !ok{
      fmt.eprintln("error: could not load update_and_draw proc");
      return false;
   } 

    {
        _ok, file_time := get_file_time(name);
        if !_ok {
            fmt.println("error getting write time");
            fmt.eprintln("could not read DLL write time:", temp_path);
            return false;
        }
        plugin.last_write_time = file_time;
    }

    plugin.name = name;
    plugin.module = new_dll;
    plugin.path_on_disk = name;
    plugin.on_load_proc = on_load_proc;
    plugin.on_unload_proc = on_unload_proc;
    plugin.update_and_draw_proc = update_and_draw_proc;

    plugin.on_load_proc(cur_state);

    return true;
}

plugin_unload :: proc(plugin: ^Plugin, cur_state : ^State) {
    if plugin.module == nil do return;

    plugin.on_unload_proc(cur_state);
    lib.unload_library(plugin.module);
    plugin.module = nil;
}

plugin_maybe_reload :: proc(plugin: ^Plugin, cur_state: ^State, force_reload: bool = false) {
    ok, file_time := get_file_time(plugin.path_on_disk);
    if !ok {
        //fmt.eprintln("could not get file time of plugin:", plugin.path_on_disk);
        return;
    }

    if !force_reload && file_time == plugin.last_write_time do return;

    plugin.last_write_time = file_time;

    plugin_unload(plugin,cur_state);
    plugin_load(plugin, plugin.name,cur_state);
}

plugin_force_reload :: proc(plugin: ^Plugin, cur_state : ^State) {
    plugin_maybe_reload(plugin, cur_state, true);
}

_recompile_script: win32.LPWSTR;
_directory_to_watch: win32.LPWSTR;


compile_game_dll :: proc() -> bool {
    startup_info : win32.LPSTARTUPINFO;
    //startup_info.cb = size_of(win32.LPSTARTUPINFO);

    process_information: win32.LPPROCESS_INFORMATION;

    if ok := win32.CreateProcessW(nil, _recompile_script, nil, nil, false, 0, nil,  nil, startup_info, process_information); !ok {
        fmt.eprintln("could not invoke build script");
        return false;
    }

    if win32.WAIT_OBJECT_0 != win32.WaitForSingleObject(process_information.hProcess, win32.INFINITE) {
        fmt.eprintln("ERROR invoking build batch file");
        return false;
    }


    // TODO: something like win32.destroy_handle(process_information.process);

    return true;
}

//TODO(Fausto): Implement FindFirstChangeNotificationA for this proc to work
watcher_thread_proc :: proc(^thread.Thread){
    fmt.println("watching for changes in", _directory_to_watch);

   watch_subtree : win32.BOOL = true;
   filter : u32;
   filter = win32.FILE_NOTIFY_CHANGE_LAST_WRITE;
   FALSE:win32.BOOL = false;
                                                                                       //V-this read perm. incase we crash so we can get agin
   hDirectory : win32.HANDLE = win32.CreateFileW(_directory_to_watch,win32.GENERIC_READ,win32.FILE_SHARE_READ,nil,win32.OPEN_EXISTING,win32.FILE_FLAG_BACKUP_SEMANTICS,nil);//Get the handle to existing directory (per microsoft docs)
   lpBuffer   : win32.FILE_NOTIFY_INFORMATION;
   win32.ReadDirectoryChangesW(hDirectory, cast(win32.LPVOID)&lpBuffer,size_of(win32.FILE_NOTIFY_INFORMATION),watch_subtree , filter,nil,nil,nil);
    if hDirectory == win32.INVALID_HANDLE {
        fmt.eprintln("FindFirstChangeNotification failed");
        //return -1;
        return;
    }

    next_timeout_ms:u32 = win32.INFINITE;
    did_get_change := false;

    for {
        wait_status := win32.WaitForSingleObject(hDirectory, next_timeout_ms);

        switch wait_status {
            case win32.WAIT_OBJECT_0:
                // when we get a file change notification, it's often immediately followed by another one.
                // so we'll lower our timeout and use that as a signal to actually recompile, to coalesce
                // multiple updates into one.
                next_timeout_ms = 150;
                did_get_change = true;
            case win32.WAIT_TIMEOUT:
                if !did_get_change {
                    fmt.println("error: infinite timeout triggered");
                    //return -1;
                    return;
                }

                // actually recompile the game.dll
                did_get_change = false;
                next_timeout_ms = win32.INFINITE;
                if ok := compile_game_dll(); !ok {
                    fmt.eprintln("result:", ok);
                }
            case:
                fmt.eprintln("unhandled wait_status", wait_status);
                //return -1;
                return;
        }

//        if win32.FindNextChangeNotification(handle) == FALSE {
            //fmt.eprintln("error in find_next_change_notification");
            ////return -1;
            //return;
        //}
    //}

    //return 0;
//    return;
    }
    return;
}

start_reload_thread :: proc(recompile_script: string, directory_to_watch: string) -> ^thread.Thread {
    assert(_recompile_script == nil, "only one reloader thread can exist at once");

    _recompile_script   = win32.utf8_to_wstring(recompile_script);
    _directory_to_watch = win32.utf8_to_wstring(directory_to_watch);

    watcher_thread := thread.create(watcher_thread_proc);
    thread.start(watcher_thread);
    return watcher_thread;
}

finish_reload_thread :: proc(watcher_thread: ^thread.Thread) {
    // TODO: signal to thread it should exit gracefully with CreateEvent like https://docs.microsoft.com/en-us/windows/desktop/sync/using-event-objects
}