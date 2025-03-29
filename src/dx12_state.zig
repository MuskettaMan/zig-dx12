const std = @import("std");

const zwindows = @import("zwindows");
const windows = zwindows.windows;
const dxgi = zwindows.dxgi;
const d3d12 = zwindows.d3d12;
const d3d12d = zwindows.d3d12d;
const hrPanicOnFail = zwindows.hrPanicOnFail;

const num_frames = 2;
const debug_enabled = true;

pub const Dx12State = struct {
    dxgi_factory: *dxgi.IFactory6,
    device: *d3d12.IDevice9,

    swap_chain: *dxgi.ISwapChain3,
    swap_chain_textures: [num_frames]*d3d12.IResource,

    rtv_heap: *d3d12.IDescriptorHeap,
    rtv_heap_start: d3d12.CPU_DESCRIPTOR_HANDLE,

    frame_fence: *d3d12.IFence,
    frame_fence_event: windows.HANDLE,
    frame_fence_counter: u64 = 0,
    frame_index: u32 = 0,

    command_queue: *d3d12.ICommandQueue,
    command_allocators: [num_frames]*d3d12.ICommandAllocator,
    command_list: *d3d12.IGraphicsCommandList6,

    pub fn init(window: windows.HWND) Dx12State {
        var dxgi_factory: *dxgi.IFactory6 = undefined;

        hrPanicOnFail(dxgi.CreateDXGIFactory2(0, &dxgi.IID_IFactory6, @ptrCast(&dxgi_factory)));

        std.log.info("DXGI factory created", .{});

        {
            var maybe_debug: ?*d3d12d.IDebug1 = null;
            _ = d3d12.GetDebugInterface(&d3d12d.IID_IDebug1, @ptrCast(&maybe_debug));
            if (maybe_debug) |debug| {
                if (debug_enabled) {
                    debug.EnableDebugLayer();
                }
                _ = debug.Release();
            }
        }

        var device: *d3d12.IDevice9 = undefined;
        if(d3d12.CreateDevice(null, .@"11_0", &d3d12.IID_IDevice9, @ptrCast(&device)) != windows.S_OK) {
            _ = windows.MessageBoxA(
                window, 
                "Failed to create Direct3D 12 Device. This applications requires graphics card " ++
                    "with DirectX 12 Feature Level 11.0 support.", 
                "Your graphics card driver may be old", 
                windows.MB_OK | windows.MB_ICONERROR
            );
            windows.ExitProcess(0);
        }
        std.log.info("D3D12 device created", .{});

        var command_queue: *d3d12.ICommandQueue = undefined;
        hrPanicOnFail(device.CreateCommandQueue(&.{
            .Type = .DIRECT,
            .Priority = @intFromEnum(d3d12.COMMAND_QUEUE_PRIORITY.NORMAL),
            .Flags = .{},
            .NodeMask = 0,
        }, &d3d12.IID_ICommandQueue, @ptrCast(&command_queue)));

        std.log.info("D3D12 command queue created", .{});

        var rect: windows.RECT = undefined;
        _ = windows.GetClientRect(window, &rect);

        var swap_chain: *dxgi.ISwapChain3 = undefined;
        {
            var desc = dxgi.SWAP_CHAIN_DESC {
                .BufferDesc = .{
                    .Width = @intCast(rect.right),
                    .Height = @intCast(rect.bottom),
                    .RefreshRate = .{ .Numerator = 0, .Denominator = 0 },
                    .Format = .R8G8B8A8_UNORM,
                    .ScanlineOrdering = .UNSPECIFIED,
                    .Scaling = .UNSPECIFIED
                },
                .SampleDesc = .{ .Count = 1, .Quality = 0 },
                .BufferUsage = .{ .RENDER_TARGET_OUTPUT = true },
                .BufferCount = num_frames,
                .OutputWindow = window,
                .Windowed = windows.TRUE,
                .SwapEffect = .FLIP_DISCARD,
                .Flags = .{} 
            };
            var temp_swap_chain: *dxgi.ISwapChain = undefined;
            hrPanicOnFail(dxgi_factory.CreateSwapChain(@ptrCast(command_queue), &desc, @ptrCast(&temp_swap_chain)));

            defer _ = temp_swap_chain.Release();

            hrPanicOnFail(temp_swap_chain.QueryInterface(&dxgi.IID_ISwapChain3, @ptrCast(&swap_chain)));
        }

        hrPanicOnFail(dxgi_factory.MakeWindowAssociation(window, .{ .NO_WINDOW_CHANGES = true }));

        var swap_chain_textures: [num_frames]*d3d12.IResource = undefined;

        for(&swap_chain_textures , 0..) |*texture, i| {
            hrPanicOnFail(swap_chain.GetBuffer(@intCast(i), &d3d12.IID_IResource, @ptrCast(&texture.*)));
        }

        std.log.info("Swap chain created", .{});

        var rtv_heap: *d3d12.IDescriptorHeap = undefined;
        hrPanicOnFail(device.CreateDescriptorHeap(&.{
            .Type = .RTV,
            .NumDescriptors = 16,
            .Flags = .{},
            .NodeMask = 0,
        }, &d3d12.IID_IDescriptorHeap, @ptrCast(&rtv_heap)));

        const rtv_heap_start = rtv_heap.GetCPUDescriptorHandleForHeapStart();

        for(swap_chain_textures, 0..) |texture, i| {
            device.CreateRenderTargetView(texture, null, .{ .ptr = rtv_heap_start.ptr + i * device.GetDescriptorHandleIncrementSize(.RTV) });
        }

        std.log.info("RTV heap created", .{});

        var frame_fence: *d3d12.IFence = undefined;
        hrPanicOnFail(device.CreateFence(0, .{}, &d3d12.IID_IFence, @ptrCast(&frame_fence)));

        const frame_fence_event = windows.CreateEventExA(null, "frame_fence_event", 0, windows.EVENT_ALL_ACCESS).?;

        std.log.info("Frame fence event created", .{});

        var command_allocators: [num_frames]*d3d12.ICommandAllocator = undefined;

        for(&command_allocators) |*cmdAlloc| {
            hrPanicOnFail(device.CreateCommandAllocator(.DIRECT, &d3d12.IID_ICommandAllocator, @ptrCast(&cmdAlloc.*)));
        }

        std.log.info("Command allocators created", .{});

        var command_list: *d3d12.IGraphicsCommandList6 = undefined;
        hrPanicOnFail(device.CreateCommandList(0, .DIRECT, command_allocators[0], null, &d3d12.IID_IGraphicsCommandList6, @ptrCast(&command_list)));
        hrPanicOnFail(command_list.Close());

        return .{
            .dxgi_factory = dxgi_factory,
            .device = device,
            .command_queue = command_queue,
            .swap_chain = swap_chain,
            .swap_chain_textures = swap_chain_textures,
            .rtv_heap = rtv_heap,
            .rtv_heap_start = rtv_heap_start,
            .frame_fence = frame_fence,
            .frame_fence_event = frame_fence_event,
            .command_allocators = command_allocators,
            .command_list = command_list,
        };
    }

    pub fn deinit(dx12: *Dx12State) void {
        _ = dx12.command_list.Release();
        for(dx12.command_allocators) |commandAlloc| _ = commandAlloc.Release();
        _ = dx12.frame_fence.Release();
        _ = windows.CloseHandle(dx12.frame_fence_event);
        _ = dx12.rtv_heap.Release();
        for(dx12.swap_chain_textures) |swap_chain_texture| _ = swap_chain_texture.Release();
        _ = dx12.swap_chain.Release();
        _ = dx12.command_queue.Release();
        _ = dx12.device.Release();
        _ = dx12.dxgi_factory.Release();
        dx12.* = undefined;
    }

    pub fn present(dx12: *Dx12State) void {
        dx12.frame_fence_counter += 1;

        hrPanicOnFail(dx12.swap_chain.Present(1, .{}));
        hrPanicOnFail(dx12.command_queue.Signal(dx12.frame_fence, dx12.frame_fence_counter));
    
        const gpu_frame_counter = dx12.frame_fence.GetCompletedValue();
        if((dx12.frame_fence_counter - gpu_frame_counter) >= num_frames) {
            hrPanicOnFail(dx12.frame_fence.SetEventOnCompletion(gpu_frame_counter + 1, dx12.frame_fence_event));
            windows.WaitForSingleObject(dx12.frame_fence_event, windows.INFINITE) catch {};
        }

        dx12.frame_index = (dx12.frame_index + 1) % num_frames;
    }

    pub fn flush(dx12: *Dx12State) void {
        dx12.frame_fence_counter += 1;

        hrPanicOnFail(dx12.command_queue.Signal(dx12.frame_fence, dx12.frame_fence_counter));
        hrPanicOnFail(dx12.frame_fence.SetEventOnCompletion(dx12.frame_fence_counter, dx12.frame_fence_event));

        windows.WaitForSingleObject(dx12.frame_fence_event, windows.INFINITE) catch {};
    }
};
