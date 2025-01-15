package main

// Import necessary packages
import "base:runtime"
import "vendor:glfw"
import vk "vendor:vulkan"
import "core:fmt"
import "core:strings"
import "core:math/bits"
import "core:os"

// Constants
WINDOW_WIDTH :: 800
WINDOW_HEIGHT :: 600

VK_DEBUG :: true

MAX_FRAMES_IN_FLIGHT :: 2

// Validation Layers to enable if VK_DEBUG is true
VALIDATION_LAYERS := []cstring{"VK_LAYER_KHRONOS_validation"}

// Global Variables
window: glfw.WindowHandle

instance: vk.Instance
debugMessenger: vk.DebugUtilsMessengerEXT
physicalDevice: vk.PhysicalDevice = nil
device: vk.Device
graphicsQueue: vk.Queue
presentQueue: vk.Queue
surface: vk.SurfaceKHR
swapChain: vk.SwapchainKHR
swapChainImages: []vk.Image
swapChainImageFormat: vk.Format
swapChainExtent: vk.Extent2D
swapChainImageViews: []vk.ImageView
deviceExtensions :: []cstring{vk.KHR_SWAPCHAIN_EXTENSION_NAME}
pipelineLayout: vk.PipelineLayout
renderPass: vk.RenderPass
graphicsPipeline: vk.Pipeline
swapChainFrameBuffers: []vk.Framebuffer
commandPool: vk.CommandPool
commandBuffers: []vk.CommandBuffer
imageAvailableSemaphores: []vk.Semaphore
renderFinishedSemaphores: []vk.Semaphore
inFlightFences: []vk.Fence
currentFrame: u32 = 0
framebufferResized: bool = false
applicationFrozen: bool = false

// Struct Definitions

// Represents a single queue family
QueueFamily :: struct {
    index: int,
    found: bool,
}

// Holds indices for graphics and presentation queue families
QueueFamilyIndices :: struct {
    graphics: QueueFamily,
    present: QueueFamily,
}

// Details about swap chain support
SwapChainSupportDetails :: struct {
    capabilities: vk.SurfaceCapabilitiesKHR,
    formats: []vk.SurfaceFormatKHR,
    presentModes: []vk.PresentModeKHR,
}

// Entry point of the application
main :: proc() {
    run()
}

// Runs the application
run :: proc() {
    defer cleanup() // Ensure cleanup is called on exit
    initWindow()
    initVulkan()
    mainLoop()
}

/* -----------------------
   Initialization Functions
   ----------------------- */

// Initializes the GLFW window
initWindow :: proc() { 
    glfw.SetErrorCallback(glfw.ErrorProc(glfwErrorCallback))

    assert(glfw.Init() == glfw.TRUE)
    
    glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
    glfw.WindowHint(glfw.RESIZABLE, glfw.FALSE)

    window = glfw.CreateWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "Vulkan", nil, nil)
    assert(window != nil)

    glfw.SetFramebufferSizeCallback(window, glfw.FramebufferSizeProc(framebufferResizeCallback))
    glfw.SetWindowIconifyCallback(window, glfw.WindowIconifyProc(windowIconifyCallback))
}

// Callback for window iconification (minimize/maximize)
windowIconifyCallback :: proc(window: glfw.WindowHandle, iconified: bool) {
    applicationFrozen = iconified
}

// Callback for framebuffer resize events
framebufferResizeCallback :: proc(window: glfw.WindowHandle, width: int, height: int) {
    framebufferResized = true
}

// Initializes Vulkan by setting up all necessary Vulkan objects
initVulkan :: proc() {
    if createInstance() != vk.Result.SUCCESS do return
    when VK_DEBUG {
        if setupDebugMessenger() != vk.Result.SUCCESS {
            fmt.eprintln("Could not setup the debug messenger")
        } else {
            fmt.println("Debug messenger setup successfully")
        }
    }
    if createSurface() != vk.Result.SUCCESS do return
    if pickPhysicalDevice() != vk.Result.SUCCESS do return
    if createLogicalDevice() != vk.Result.SUCCESS do return
    if createSwapChain() != vk.Result.SUCCESS do return
    if createImageViews() != vk.Result.SUCCESS do return
    if createRenderPass() != vk.Result.SUCCESS do return
    if createGraphicsPipeline() != vk.Result.SUCCESS do return
    if createFrameBuffers() != vk.Result.SUCCESS do return
    if createCommandPool() != vk.Result.SUCCESS do return
    if createCommandBuffers() != vk.Result.SUCCESS do return
    if createSyncObjects() != vk.Result.SUCCESS do return
}

/* -----------------------
   Vulkan Setup Functions
   ----------------------- */

// Creates the Vulkan instance
createInstance :: proc() -> vk.Result {
    vk.load_proc_addresses(rawptr(glfw.GetInstanceProcAddress))

    // Application info (optional but recommended)
    appInfo := vk.ApplicationInfo{
        sType=              vk.StructureType.APPLICATION_INFO,
        pApplicationName=   "Hello Triangle",
        pEngineName=        "No Engine",
        engineVersion=      vk.MAKE_VERSION(1, 0, 0),
        apiVersion=         vk.API_VERSION_1_3,
    }

    // Instance creation info
    createInfo := vk.InstanceCreateInfo{
        sType=                 vk.StructureType.INSTANCE_CREATE_INFO,
        pApplicationInfo=      &appInfo,
    }
    
    // Get required extensions
    extensions := getRequiredExtensions()
    createInfo.enabledExtensionCount = cast(u32)len(extensions)
    createInfo.ppEnabledExtensionNames = raw_data(extensions)

    // Enable validation layers if in debug mode
    when VK_DEBUG {
        assert (checkValidationLayerSupport())
        createInfo.enabledLayerCount = cast(u32)len(VALIDATION_LAYERS)
        createInfo.ppEnabledLayerNames = raw_data(VALIDATION_LAYERS)

        debugCreateInfo: vk.DebugUtilsMessengerCreateInfoEXT 
        populateDebugMessengerCreateInfo(&debugCreateInfo)
        createInfo.pNext = &debugCreateInfo

    } else {
        createInfo.enabledLayerCount = 0
        createInfo.pNext = nil
    }

    // Create the Vulkan instance
    result: vk.Result = vk.CreateInstance(&createInfo, nil, &instance)
    if (result != vk.Result.SUCCESS) {
        fmt.eprintln("Could not initialize the Vulkan Instance")
        return vk.Result.ERROR_INITIALIZATION_FAILED   
    } else {
        fmt.println("Vulkan Instance created successfully")
    }

    // Load Vulkan procedures for the created instance
    vk.load_proc_addresses(instance)
    return vk.Result.SUCCESS
}

// Sets up the debug messenger for validation layers
setupDebugMessenger :: proc() -> vk.Result {
    createInfo: vk.DebugUtilsMessengerCreateInfoEXT
    populateDebugMessengerCreateInfo(&createInfo)
    procedure := auto_cast vk.ProcCreateDebugUtilsMessengerEXT(vk.GetInstanceProcAddr(instance, "vkCreateDebugUtilsMessengerEXT"))
    if procedure != nil {
        return procedure(instance, &createInfo, nil, &debugMessenger)
    }
    return vk.Result.ERROR_EXTENSION_NOT_PRESENT
}

// Populates the debug messenger create info structure
populateDebugMessengerCreateInfo :: proc(createInfo: ^vk.DebugUtilsMessengerCreateInfoEXT) {
    createInfo^.sType = vk.StructureType.DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT
    createInfo^.messageSeverity = vk.DebugUtilsMessageSeverityFlagsEXT{.VERBOSE, .WARNING, .ERROR}
    createInfo^.messageType = vk.DebugUtilsMessageTypeFlagsEXT{.GENERAL, .VALIDATION, .PERFORMANCE}
    createInfo^.pfnUserCallback = vk.ProcDebugUtilsMessengerCallbackEXT(debugCallback)
    createInfo^.pUserData = nil
}

// Debug callback function for validation layers
debugCallback :: proc (
    messageSeverity: vk.DebugUtilsMessageSeverityFlagsEXT,
    messageType: vk.DebugUtilsMessageTypeFlagsEXT,
    pCallbackData: ^vk.DebugUtilsMessengerCallbackDataEXT,
    pUserData: rawptr
) -> b32 {
    fmt.eprintln("validation layer: ", cstring(pCallbackData.pMessage))
    return false
}

// Retrieves the required Vulkan extensions
getRequiredExtensions :: proc() -> [dynamic]cstring {
    extensions := [dynamic]cstring{}
    glfwExtensions := glfw.GetRequiredInstanceExtensions()
    append_elems(&extensions, ..glfwExtensions)
    when VK_DEBUG {
        append_elems(&extensions, vk.EXT_DEBUG_UTILS_EXTENSION_NAME)
    }
    return extensions
}

// Checks if all requested validation layers are available
checkValidationLayerSupport :: proc() -> bool {
    layerCount: u32
    vk.EnumerateInstanceLayerProperties(&layerCount, nil)
    availableLayers := make([]vk.LayerProperties, layerCount)
    vk.EnumerateInstanceLayerProperties(&layerCount, raw_data(availableLayers))

    for &layerName in VALIDATION_LAYERS {
        layerFound := false
        for &layerProperties in availableLayers {
            if layerName == cstring(&layerProperties.layerName[0]) {
                layerFound = true
                break
            }
        }
        if (!layerFound) {
            return false
        }
    }
    return true
}

// Creates the window surface using GLFW
createSurface :: proc() -> vk.Result {
    if glfw.CreateWindowSurface(instance, window, nil, &surface) != vk.Result.SUCCESS {
        fmt.eprintln("Failed to create window surface")
        return vk.Result.ERROR_INITIALIZATION_FAILED
    } else {
        fmt.println("Window surface created successfully")
        return vk.Result.SUCCESS
    }
}

// Selects a suitable physical device (GPU) for Vulkan operations
pickPhysicalDevice :: proc() -> vk.Result {
    deviceCount: u32

    fmt.println("Picking a physical device...")
    vk.EnumeratePhysicalDevices(instance, &deviceCount, nil)
    fmt.println("Found ", deviceCount, " devices with Vulkan support.")
    if deviceCount == 0 {
        fmt.eprintln("Failed to find GPUs with Vulkan support.")
        return vk.Result.ERROR_INITIALIZATION_FAILED
    }

    devices := make([]vk.PhysicalDevice, deviceCount)
    vk.EnumeratePhysicalDevices(instance, &deviceCount, raw_data(devices))

    currentScore, maxScore := 0.0, 0.0

    for &device in devices {
        if isDeviceSuitable(device) {
            currentScore = cast(f64)rateDeviceSuitability(device)
            if currentScore > maxScore {
                physicalDevice = device
                maxScore = currentScore
            }
        }
    }

    if physicalDevice == nil {
        fmt.eprintln("Failed to find a suitable GPU!")
        return vk.Result.ERROR_INITIALIZATION_FAILED
    } else {
        fmt.println("Found a suitable GPU!")
    }

    return vk.Result.SUCCESS
}

// Rates the suitability of a physical device
rateDeviceSuitability :: proc(device: vk.PhysicalDevice) -> f32 {
    score: f32 = 0
    deviceProperties: vk.PhysicalDeviceProperties
    deviceFeatures: vk.PhysicalDeviceFeatures
    vk.GetPhysicalDeviceProperties(device, &deviceProperties)
    vk.GetPhysicalDeviceFeatures(device, &deviceFeatures)

    if (deviceProperties.deviceType == vk.PhysicalDeviceType.DISCRETE_GPU) {
        score += 1000
    }
    // Additional scoring based on device properties can be added here

    return score
}

// Checks if a device is suitable for our needs
isDeviceSuitable :: proc(device: vk.PhysicalDevice) -> bool {
    deviceFeatures: vk.PhysicalDeviceFeatures
    vk.GetPhysicalDeviceFeatures(device, &deviceFeatures)

    indices: QueueFamilyIndices = findQueueFamilies(device)

    extensionsSupported := checkDeviceExtensionSupport(device)
    swapChainAdequate := false
    if extensionsSupported {
        swapChainSupport := querySwapChainSupport(device)
        swapChainAdequate = len(swapChainSupport.formats) != 0 && len(swapChainSupport.presentModes) != 0
    }

    if deviceFeatures.geometryShader && hasAllQueueFamilies(indices) && swapChainAdequate {
        return true
    }

    fmt.eprintln("Device not suitable")
    return false
}

// Checks if all required device extensions are supported
checkDeviceExtensionSupport :: proc(device: vk.PhysicalDevice) -> bool {
    extensionCount: u32
    vk.EnumerateDeviceExtensionProperties(device, nil, &extensionCount, nil)

    availableExtensions := make([]vk.ExtensionProperties, extensionCount)
    vk.EnumerateDeviceExtensionProperties(device, nil, &extensionCount, raw_data(availableExtensions))

    requiredExtensions: map[cstring]bool

    for extension in deviceExtensions {
        requiredExtensions[extension] = true
    }

    for &extension in availableExtensions {
        if (requiredExtensions[cstring(&extension.extensionName[0])]) {
            requiredExtensions[cstring(&extension.extensionName[0])] = false
        }
    }

    for _, value in requiredExtensions {
        if value {
            return false
        }
    }
    return true
}

// Finds the queue families for graphics and presentation
findQueueFamilies :: proc(device: vk.PhysicalDevice) -> QueueFamilyIndices {
    queueFamilyIndices: QueueFamilyIndices

    queueFamilyCount: u32
    vk.GetPhysicalDeviceQueueFamilyProperties(device, &queueFamilyCount, nil)

    queueFamilies := make([]vk.QueueFamilyProperties, queueFamilyCount)
    vk.GetPhysicalDeviceQueueFamilyProperties(device, &queueFamilyCount, raw_data(queueFamilies))

    for &queueFamily, i in queueFamilies {
        // Check for graphics support
        if vk.QueueFlag.GRAPHICS in queueFamily.queueFlags {
            if !queueFamilyIndices.graphics.found {
                queueFamilyIndices.graphics.found = true
                queueFamilyIndices.graphics.index = i
            }
        }

        // Check for presentation support
        presentSupport: b32
        vk.GetPhysicalDeviceSurfaceSupportKHR(device, cast(u32)(i), surface, &presentSupport)
        if presentSupport {
            if !queueFamilyIndices.present.found {
                queueFamilyIndices.present.found = true
                queueFamilyIndices.present.index = i
            }
        }

        // Break early if both families are found
        if queueFamilyIndices.graphics.found && queueFamilyIndices.present.found {
            break
        }
    }

    return queueFamilyIndices
}

// Ensures all required queue families are found
hasAllQueueFamilies :: proc(indices: QueueFamilyIndices) -> bool {
    return indices.graphics.found && indices.present.found
}

// Creates the logical device and retrieves queue handles
createLogicalDevice :: proc() -> vk.Result {
    indices: QueueFamilyIndices = findQueueFamilies(physicalDevice)
    queueCreateInfos := [dynamic]vk.DeviceQueueCreateInfo{}

    queuePriority: f32 = 1.0

    uniqueQueueFamilies := map[int]bool{
        indices.graphics.index= true,
        indices.present.index=  true,
    }

    for queueFamily in uniqueQueueFamilies {
        queueCreateInfo := vk.DeviceQueueCreateInfo{
            sType=            vk.StructureType.DEVICE_QUEUE_CREATE_INFO,
            queueFamilyIndex= cast(u32)queueFamily,
            queueCount=       1,
            pQueuePriorities= raw_data([]f32{queuePriority}),
        }
        append_elem(&queueCreateInfos, queueCreateInfo)
    }

    deviceFeatures: vk.PhysicalDeviceFeatures // Initialize with default features
    createInfo := vk.DeviceCreateInfo{
        sType=                   vk.StructureType.DEVICE_CREATE_INFO,
        pQueueCreateInfos=       raw_data(queueCreateInfos),
        queueCreateInfoCount=    cast(u32)len(queueCreateInfos),
        pEnabledFeatures=        &deviceFeatures,
        enabledExtensionCount=   cast(u32)len(deviceExtensions),
        ppEnabledExtensionNames= raw_data(deviceExtensions),
    }

    // Enable validation layers for the device if in debug mode
    when VK_DEBUG {
        createInfo.enabledLayerCount = cast(u32)len(VALIDATION_LAYERS)
        createInfo.ppEnabledLayerNames = raw_data(VALIDATION_LAYERS)
    } else {
        createInfo.enabledLayerCount = 0
    }

    // Create the logical device
    if vk.CreateDevice(physicalDevice, &createInfo, nil, &device) != vk.Result.SUCCESS {
        fmt.eprintln("Failed to create logical device")
        return vk.Result.ERROR_INITIALIZATION_FAILED
    }

    // Retrieve queue handles
    vk.GetDeviceQueue(device, cast(u32)indices.graphics.index, 0, &graphicsQueue)
    vk.GetDeviceQueue(device, cast(u32)indices.present.index, 0, &presentQueue)

    return vk.Result.SUCCESS
}

// Creates the swap chain based on device and surface capabilities
createSwapChain :: proc() -> vk.Result {
    swapChainSupport: SwapChainSupportDetails = querySwapChainSupport(physicalDevice)
    
    surfaceFormat := chooseSwapSurfaceFormat(swapChainSupport.formats)
    presentMode := chooseSwapPresentMode(swapChainSupport.presentModes)
    extent := chooseSwapExtent(swapChainSupport.capabilities)

    imageCount := swapChainSupport.capabilities.minImageCount + 1

    if swapChainSupport.capabilities.maxImageCount > 0 && imageCount > swapChainSupport.capabilities.maxImageCount {
        imageCount = swapChainSupport.capabilities.maxImageCount
    }

    // Create the swap chain
    createInfo := vk.SwapchainCreateInfoKHR{
        sType=                 vk.StructureType.SWAPCHAIN_CREATE_INFO_KHR,
        surface=               surface,
        minImageCount=         imageCount,
        imageFormat=           surfaceFormat.format,
        imageColorSpace=       surfaceFormat.colorSpace,
        imageExtent=           extent,
        imageArrayLayers=      1,
        imageUsage=            vk.ImageUsageFlags{.COLOR_ATTACHMENT},
    }

    indices: QueueFamilyIndices = findQueueFamilies(physicalDevice)
    queueFamilyIndices: []u32 = {cast(u32)indices.graphics.index, cast(u32)indices.present.index}
    
    if indices.graphics.index != indices.present.index {
        createInfo.imageSharingMode = vk.SharingMode.CONCURRENT
        createInfo.queueFamilyIndexCount = 2
        createInfo.pQueueFamilyIndices = raw_data(queueFamilyIndices)
    } else {
        createInfo.imageSharingMode = vk.SharingMode.EXCLUSIVE
        createInfo.queueFamilyIndexCount = 0
        createInfo.pQueueFamilyIndices = nil
    }

    createInfo.preTransform = swapChainSupport.capabilities.currentTransform
    createInfo.compositeAlpha = vk.CompositeAlphaFlagsKHR{.OPAQUE}
    createInfo.presentMode = presentMode
    createInfo.clipped = true

    // Create the swap chain
    if vk.CreateSwapchainKHR(device, &createInfo, nil, &swapChain) != vk.Result.SUCCESS {
        fmt.eprintln("Failed to create swap chain")
        return vk.Result.ERROR_INITIALIZATION_FAILED
    } else {
        fmt.println("Swap chain created successfully")
    }

    // Retrieve swap chain images
    vk.GetSwapchainImagesKHR(device, swapChain, &imageCount, nil)
    swapChainImages = make([]vk.Image, imageCount)
    vk.GetSwapchainImagesKHR(device, swapChain, &imageCount, raw_data(swapChainImages))

    swapChainImageFormat = surfaceFormat.format
    swapChainExtent = extent
    
    return vk.Result.SUCCESS
}

// Queries swap chain support details for a physical device
querySwapChainSupport :: proc(device: vk.PhysicalDevice) -> SwapChainSupportDetails {
    details: SwapChainSupportDetails
    vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(device, surface, &details.capabilities)

    // Get surface formats
    formatCount: u32
    vk.GetPhysicalDeviceSurfaceFormatsKHR(device, surface, &formatCount, nil)

    if formatCount != 0 {
        details.formats = make([]vk.SurfaceFormatKHR, formatCount)
        vk.GetPhysicalDeviceSurfaceFormatsKHR(device, surface, &formatCount, raw_data(details.formats))
    }

    // Get present modes
    presentModeCount: u32
    vk.GetPhysicalDeviceSurfacePresentModesKHR(device, surface, &presentModeCount, nil)

    if presentModeCount != 0 {
        details.presentModes = make([]vk.PresentModeKHR, presentModeCount)
        vk.GetPhysicalDeviceSurfacePresentModesKHR(device, surface, &presentModeCount, raw_data(details.presentModes))
    }

    return details
}

// Chooses the best surface format from available options
chooseSwapSurfaceFormat :: proc(availableFormats: []vk.SurfaceFormatKHR) -> vk.SurfaceFormatKHR {
    for availableFormat in availableFormats {
        if availableFormat.format == vk.Format.B8G8R8A8_SRGB && availableFormat.colorSpace == vk.ColorSpaceKHR.SRGB_NONLINEAR {
            return availableFormat
        }
    }
    return availableFormats[0]
}

// Chooses the best present mode from available options
chooseSwapPresentMode :: proc(availablePresentModes: []vk.PresentModeKHR) -> vk.PresentModeKHR {
    for &availablePresentMode in availablePresentModes {
        if availablePresentMode == vk.PresentModeKHR.MAILBOX {
            return availablePresentMode
        }
    }

    // Fallback to FIFO which is guaranteed to be available
    return vk.PresentModeKHR.FIFO
}

// Chooses the swap extent (resolution) for the swap chain
chooseSwapExtent :: proc(capabilities: vk.SurfaceCapabilitiesKHR) -> vk.Extent2D {
    if capabilities.currentExtent.width != bits.U32_MAX {
        return capabilities.currentExtent 
    } else {
        width, height := glfw.GetFramebufferSize(window)

        actualExtent: vk.Extent2D = {
            width=  cast(u32) width,
            height= cast(u32) height,
        }

        // Clamp the extent within allowed bounds
        actualExtent.width = clamp(actualExtent.width, capabilities.minImageExtent.width, capabilities.maxImageExtent.width)
        actualExtent.height = clamp(actualExtent.height, capabilities.minImageExtent.height, capabilities.maxImageExtent.height)

        return actualExtent
    }
}

// Creates image views for all swap chain images
createImageViews :: proc() -> vk.Result {
    swapChainImageViews = make([]vk.ImageView, len(swapChainImages))
    for i := 0; i < len(swapChainImages); i += 1 {
        createInfo: vk.ImageViewCreateInfo = {
            sType=            vk.StructureType.IMAGE_VIEW_CREATE_INFO,
            image=            swapChainImages[i],
            viewType=         vk.ImageViewType.D2,
            format=           swapChainImageFormat,
            components=      vk.ComponentMapping{
                r= vk.ComponentSwizzle.IDENTITY,
                g= vk.ComponentSwizzle.IDENTITY,
                b= vk.ComponentSwizzle.IDENTITY,
                a= vk.ComponentSwizzle.IDENTITY,
            },
            subresourceRange= vk.ImageSubresourceRange{
                aspectMask=     vk.ImageAspectFlags{.COLOR},
                baseMipLevel=   0,
                levelCount=     1,
                baseArrayLayer= 0,
                layerCount=     1,
            },
        }
        if vk.CreateImageView(device, &createInfo, nil, &swapChainImageViews[i]) != vk.Result.SUCCESS {
            fmt.eprintln("Failed to create image views")
            return vk.Result.ERROR_INITIALIZATION_FAILED
        }
    }

    fmt.println("Image views created successfully")
    return vk.Result.SUCCESS
}

// Creates the render pass
createRenderPass :: proc() -> vk.Result {
    colorAttachment: vk.AttachmentDescription = {
        format=         swapChainImageFormat,
        samples=        vk.SampleCountFlags{._1},
        loadOp=         vk.AttachmentLoadOp.CLEAR,
        storeOp=        vk.AttachmentStoreOp.STORE,
        stencilLoadOp=  vk.AttachmentLoadOp.DONT_CARE,
        stencilStoreOp= vk.AttachmentStoreOp.DONT_CARE,
        initialLayout=  vk.ImageLayout.UNDEFINED,
        finalLayout=    vk.ImageLayout.PRESENT_SRC_KHR,
    }

    colorAttachmentRef: vk.AttachmentReference = {
        attachment= 0, // Attachment index in the fragment shader
        layout=     vk.ImageLayout.COLOR_ATTACHMENT_OPTIMAL,
    }

    subpass: vk.SubpassDescription = {
        pipelineBindPoint= vk.PipelineBindPoint.GRAPHICS,
        colorAttachmentCount= 1,
        pColorAttachments= &colorAttachmentRef,
    }

    // Subpass dependency for layout transitions
    dependency: vk.SubpassDependency = {
        srcSubpass=      vk.SUBPASS_EXTERNAL,
        dstSubpass=      0,
        srcStageMask=    vk.PipelineStageFlags{.COLOR_ATTACHMENT_OUTPUT},
        srcAccessMask=   {},
        dstStageMask=    vk.PipelineStageFlags{.COLOR_ATTACHMENT_OUTPUT},
        dstAccessMask=   vk.AccessFlags{.COLOR_ATTACHMENT_WRITE},
    }

    renderPassInfo: vk.RenderPassCreateInfo = {
        sType=              vk.StructureType.RENDER_PASS_CREATE_INFO,
        attachmentCount=    1,
        pAttachments=       &colorAttachment,
        subpassCount=       1,
        pSubpasses=         &subpass,
        dependencyCount=    1,
        pDependencies=      &dependency,
    }
    
    // Create the render pass
    if vk.CreateRenderPass(device, &renderPassInfo, nil, &renderPass) != vk.Result.SUCCESS {
        fmt.eprintln("Failed to create render pass")
        return vk.Result.ERROR_INITIALIZATION_FAILED
    }
    fmt.println("Render pass created successfully")
    return vk.Result.SUCCESS
}

// Creates the graphics pipeline
createGraphicsPipeline :: proc() -> vk.Result {
    // Load shader code
    vertShaderCode, ok := readFileBytes("./main/shaders/simple_vertex.spv")
    if !ok {
        return vk.Result.ERROR_INITIALIZATION_FAILED
    }
    fragShaderCode, okf := readFileBytes("./main/shaders/simple_frag.spv")
    if !okf {
        return vk.Result.ERROR_INITIALIZATION_FAILED
    }

    // Create shader modules
    vertShaderModule, vertResult := createShaderModule(vertShaderCode)
    if vertResult != vk.Result.SUCCESS do return vertResult
    fragShaderModule, fragResult := createShaderModule(fragShaderCode)
    if fragResult != vk.Result.SUCCESS do return fragResult
    defer {
        vk.DestroyShaderModule(device, vertShaderModule, nil)
        vk.DestroyShaderModule(device, fragShaderModule, nil)
    }

    // Shader stage info for vertex shader
    vertShaderStageInfo: vk.PipelineShaderStageCreateInfo = {
        sType=    vk.StructureType.PIPELINE_SHADER_STAGE_CREATE_INFO,
        stage=    vk.ShaderStageFlags{.VERTEX},
        module=   vertShaderModule,
        pName=    "main",
    }

    // Shader stage info for fragment shader
    fragShaderStageInfo: vk.PipelineShaderStageCreateInfo = {
        sType=    vk.StructureType.PIPELINE_SHADER_STAGE_CREATE_INFO,
        stage=    vk.ShaderStageFlags{.FRAGMENT},
        module=   fragShaderModule,
        pName=    "main",
    }

    shaderStages := []vk.PipelineShaderStageCreateInfo{vertShaderStageInfo, fragShaderStageInfo}

    // Dynamic states (viewport and scissor)
    dynamicStates: []vk.DynamicState = {vk.DynamicState.VIEWPORT, vk.DynamicState.SCISSOR}
    
    dynamicState: vk.PipelineDynamicStateCreateInfo = {
        sType=              vk.StructureType.PIPELINE_DYNAMIC_STATE_CREATE_INFO,
        dynamicStateCount=  cast(u32)len(dynamicStates),
        pDynamicStates=     raw_data(dynamicStates),
    }

    // Vertex input configuration (no vertex data)
    vertexInputInfo: vk.PipelineVertexInputStateCreateInfo = {
        sType=                        vk.StructureType.PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        vertexBindingDescriptionCount= 0,
        pVertexBindingDescriptions=    nil,
        vertexAttributeDescriptionCount= 0,
        pVertexAttributeDescriptions=   nil,
    }

    // Input assembly configuration (triangle list)
    inputAssembly: vk.PipelineInputAssemblyStateCreateInfo = {
        sType=                  vk.StructureType.PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        topology=               vk.PrimitiveTopology.TRIANGLE_LIST,
        primitiveRestartEnable= false,
    }

    // Viewport state (handled dynamically)
    viewportState: vk.PipelineViewportStateCreateInfo = {
        sType=        vk.StructureType.PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        viewportCount= 1,
        scissorCount=  1,
    }

    // Rasterizer configuration
    rasterizer: vk.PipelineRasterizationStateCreateInfo = {
        sType=                   vk.StructureType.PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        depthClampEnable=        false,
        rasterizerDiscardEnable= false,
        polygonMode=             vk.PolygonMode.FILL,
        lineWidth=               1.0,
        cullMode=                vk.CullModeFlags{.BACK},
        frontFace=               vk.FrontFace.CLOCKWISE,
        depthBiasEnable=         false,
        depthBiasConstantFactor= 0.0,
        depthBiasClamp=          0.0,
        depthBiasSlopeFactor=    0.0,
    }

    // Multisampling configuration (disabled)
    multiSampling: vk.PipelineMultisampleStateCreateInfo = {
        sType=                 vk.StructureType.PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        sampleShadingEnable=   false,
        rasterizationSamples=  vk.SampleCountFlags{._1},
        minSampleShading=      1.0,
        pSampleMask=           nil,
        alphaToCoverageEnable= false,
        alphaToOneEnable=      false,
    }

    // Color blending configuration (simple alpha blending)
    colorBlendAttachment: vk.PipelineColorBlendAttachmentState = {
        colorWriteMask=      vk.ColorComponentFlags{.R, .G, .B, .A},
        blendEnable=         true,
        srcColorBlendFactor= vk.BlendFactor.SRC_ALPHA,
        dstColorBlendFactor= vk.BlendFactor.ONE_MINUS_SRC_ALPHA,
        colorBlendOp=        vk.BlendOp.ADD,
        srcAlphaBlendFactor= vk.BlendFactor.ONE,
        dstAlphaBlendFactor= vk.BlendFactor.ZERO,
        alphaBlendOp=        vk.BlendOp.ADD,
    }

    colorBlending: vk.PipelineColorBlendStateCreateInfo = {
        sType=             vk.StructureType.PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
        logicOpEnable=     false,
        logicOp=           vk.LogicOp.COPY,
        attachmentCount=   1,
        pAttachments=      &colorBlendAttachment,
        blendConstants=    [4]f32{0.0, 0.0, 0.0, 0.0},
    }

    // Pipeline layout (no descriptor sets or push constants)
    pipelineLayoutInfo: vk.PipelineLayoutCreateInfo = {
        sType=                  vk.StructureType.PIPELINE_LAYOUT_CREATE_INFO,
        setLayoutCount=         0,
        pSetLayouts=            nil,
        pushConstantRangeCount= 0,
        pPushConstantRanges=    nil,
    }

    // Create the pipeline layout
    if vk.CreatePipelineLayout(device, &pipelineLayoutInfo, nil, &pipelineLayout) != vk.Result.SUCCESS {
        fmt.eprintln("Failed to create pipeline layout")
        return vk.Result.ERROR_INITIALIZATION_FAILED
    }

    // Graphics pipeline creation info
    pipelineInfo: vk.GraphicsPipelineCreateInfo = {
        sType=               vk.StructureType.GRAPHICS_PIPELINE_CREATE_INFO,
        stageCount=          2,
        pStages=             raw_data(shaderStages),
        pVertexInputState=   &vertexInputInfo,
        pInputAssemblyState= &inputAssembly,
        pViewportState=      &viewportState,
        pRasterizationState= &rasterizer,
        pMultisampleState=   &multiSampling,
        pDepthStencilState=  nil,
        pColorBlendState=    &colorBlending,
        pDynamicState=       &dynamicState,
        layout=              pipelineLayout,
        renderPass=          renderPass,
        subpass=             0,
        basePipelineIndex=   -1,
    }

    // Create the graphics pipeline
    if vk.CreateGraphicsPipelines(device, {}, 1, &pipelineInfo, nil, &graphicsPipeline) != vk.Result.SUCCESS {
        fmt.eprintln("Failed to create graphics pipeline")
        return vk.Result.ERROR_INITIALIZATION_FAILED
    }

    fmt.println("Graphics pipeline created successfully")
    return vk.Result.SUCCESS
}

// Reads a file and returns its bytes
readFileBytes :: proc(filePath: string) -> ([]byte, bool) {
    file, error := os.open(filePath)
    if error != os.ERROR_NONE {
        fmt.eprintln("Could not open file: ", filePath)
        fmt.println("Error: ", error)
        return nil, false
    }
    defer os.close(file)

    fileSize, _ := os.file_size(file)
    buffer := make([]byte, fileSize)

    os.seek(file, 0, os.SEEK_SET)
    bytesRead, bytesReadError := os.read(file, buffer)

    if bytesReadError != os.ERROR_NONE {
        fmt.eprintln("Could not read file: ", filePath)
        return nil, false
    }
    return buffer, true
}

// Creates a shader module from shader bytecode
createShaderModule :: proc(code: []byte) -> (vk.ShaderModule, vk.Result) {
    createInfo: vk.ShaderModuleCreateInfo = {
        sType=    vk.StructureType.SHADER_MODULE_CREATE_INFO,
        codeSize= len(code),
        pCode=    cast(^u32)raw_data(code),
    }
    shaderModule: vk.ShaderModule
    if vk.CreateShaderModule(device, &createInfo, nil, &shaderModule) != vk.Result.SUCCESS {
        fmt.eprintln("Failed to create shader module")
        return vk.ShaderModule{}, vk.Result.ERROR_INITIALIZATION_FAILED
    }
    return shaderModule, vk.Result.SUCCESS
}

// Creates framebuffers for each swap chain image view
createFrameBuffers :: proc() -> vk.Result {
    swapChainFrameBuffers = make([]vk.Framebuffer, len(swapChainImageViews))
    for i := 0; i < len(swapChainImageViews); i += 1 {
        attachments := []vk.ImageView{swapChainImageViews[i]}
        
        framebufferInfo: vk.FramebufferCreateInfo = {
            sType=           vk.StructureType.FRAMEBUFFER_CREATE_INFO,
            renderPass=      renderPass,
            attachmentCount= 1,
            pAttachments=    raw_data(attachments),
            width=           swapChainExtent.width,
            height=          swapChainExtent.height,
            layers=          1,
        }

        if vk.CreateFramebuffer(device, &framebufferInfo, nil, &swapChainFrameBuffers[i]) != vk.Result.SUCCESS {
            fmt.eprintln("Failed to create framebuffer")
            return vk.Result.ERROR_INITIALIZATION_FAILED
        }
    }
    fmt.println("Framebuffers created successfully")
    return vk.Result.SUCCESS
}

// Creates the command pool for allocating command buffers
createCommandPool :: proc() -> vk.Result {
    queueFamilyIndices := findQueueFamilies(physicalDevice)

    poolInfo: vk.CommandPoolCreateInfo = {
        sType=            vk.StructureType.COMMAND_POOL_CREATE_INFO,
        queueFamilyIndex= cast(u32)queueFamilyIndices.graphics.index,
        flags=            vk.CommandPoolCreateFlags{.RESET_COMMAND_BUFFER},
    }

    if vk.CreateCommandPool(device, &poolInfo, nil, &commandPool) != vk.Result.SUCCESS {
        fmt.eprintln("Failed to create command pool")
        return vk.Result.ERROR_INITIALIZATION_FAILED
    }

    fmt.println("Command pool created successfully")
    return vk.Result.SUCCESS
}

// Allocates command buffers from the command pool
createCommandBuffers :: proc() -> vk.Result {
    commandBuffers = make([]vk.CommandBuffer, MAX_FRAMES_IN_FLIGHT)
    allocInfo: vk.CommandBufferAllocateInfo = {
        sType=              vk.StructureType.COMMAND_BUFFER_ALLOCATE_INFO,
        commandPool=        commandPool,
        level=              vk.CommandBufferLevel.PRIMARY,
        commandBufferCount= MAX_FRAMES_IN_FLIGHT,
    }

    if vk.AllocateCommandBuffers(device, &allocInfo, raw_data(commandBuffers)) != vk.Result.SUCCESS {
        fmt.eprintln("Failed to allocate command buffers")
        return vk.Result.ERROR_INITIALIZATION_FAILED
    }

    fmt.println("Command buffers allocated successfully")
    return vk.Result.SUCCESS
}

// Records commands into a command buffer for a specific image index
recordCommandBuffer :: proc(commandBuffer: vk.CommandBuffer, imageIndex: u32) {
    beginInfo: vk.CommandBufferBeginInfo = {
        sType=  vk.StructureType.COMMAND_BUFFER_BEGIN_INFO,
        flags=  {.SIMULTANEOUS_USE},
        pInheritanceInfo= nil,
    }

    if vk.BeginCommandBuffer(commandBuffer, &beginInfo) != vk.Result.SUCCESS {
        fmt.eprintln("Failed to begin recording command buffer")
        return
    }
    
    // Clear color value (black)
    clearColor: vk.ClearValue = {
      color = vk.ClearColorValue{
          float32= [4]f32{0.0, 0.0, 0.0, 1.0},
      },
    }

    // Render pass begin info
    renderPassInfo: vk.RenderPassBeginInfo = {
        sType=       vk.StructureType.RENDER_PASS_BEGIN_INFO,
        renderPass=  renderPass,
        framebuffer= swapChainFrameBuffers[imageIndex],
        renderArea= vk.Rect2D{
            offset= vk.Offset2D{.0, .0},
            extent= swapChainExtent,
        },
        clearValueCount= 1,
        pClearValues=    &clearColor,
    }

    // Begin render pass
    vk.CmdBeginRenderPass(commandBuffer, &renderPassInfo, vk.SubpassContents.INLINE)
    vk.CmdBindPipeline(commandBuffer, vk.PipelineBindPoint.GRAPHICS, graphicsPipeline)

    // Dynamic viewport
    viewport: vk.Viewport = {
        x=        0.0,
        y=        0.0,
        width=    cast(f32)swapChainExtent.width,
        height=   cast(f32)swapChainExtent.height,
        minDepth= 0.0,
        maxDepth= 1.0,
    }
    vk.CmdSetViewport(commandBuffer, 0, 1, &viewport)

    // Dynamic scissor
    scissor: vk.Rect2D = {
        offset= vk.Offset2D{.0, .0},
        extent= swapChainExtent,
    }
    vk.CmdSetScissor(commandBuffer, 0, 1, &scissor)

    // Draw call (3 vertices for a triangle)
    vk.CmdDraw(commandBuffer, 3, 1, 0, 0)
    vk.CmdEndRenderPass(commandBuffer)

    // End command buffer recording
    if vk.EndCommandBuffer(commandBuffer) != vk.Result.SUCCESS {
        fmt.eprintln("Failed to record command buffer")
    }
}

// Creates synchronization objects for rendering
createSyncObjects :: proc() -> vk.Result {
    imageAvailableSemaphores = make([]vk.Semaphore, MAX_FRAMES_IN_FLIGHT)
    renderFinishedSemaphores = make([]vk.Semaphore, MAX_FRAMES_IN_FLIGHT)
    inFlightFences = make([]vk.Fence, MAX_FRAMES_IN_FLIGHT)
    
    semaphoreInfo: vk.SemaphoreCreateInfo = {
        sType= vk.StructureType.SEMAPHORE_CREATE_INFO,
    }

    fenceInfo: vk.FenceCreateInfo = {
        sType= vk.StructureType.FENCE_CREATE_INFO,
        flags= vk.FenceCreateFlags{.SIGNALED},
    }

    for i := 0; i < MAX_FRAMES_IN_FLIGHT; i += 1 {
        if vk.CreateSemaphore(device, &semaphoreInfo, nil, &imageAvailableSemaphores[i]) != vk.Result.SUCCESS ||
           vk.CreateSemaphore(device, &semaphoreInfo, nil, &renderFinishedSemaphores[i]) != vk.Result.SUCCESS ||
           vk.CreateFence(device, &fenceInfo, nil, &inFlightFences[i]) != vk.Result.SUCCESS {
            fmt.eprintln("Failed to create semaphores")
            return vk.Result.ERROR_INITIALIZATION_FAILED
        }
    }
    fmt.println("Semaphores and fences created successfully")
    return vk.Result.SUCCESS
}

/* -----------------------
   Main Loop and Rendering
   ----------------------- */

// Runs the main application loop
mainLoop :: proc() {
    fmt.println("Entering main loop. Close the window to exit.")
    for !glfw.WindowShouldClose(window) {
        if applicationFrozen {
            glfw.WaitEvents()
        } else {
            glfw.PollEvents()
            drawFrame()
        }
    }
    vk.DeviceWaitIdle(device)
    fmt.println("Exiting main loop.")
}

// Draws a single frame
drawFrame :: proc() {
    // Wait for the previous frame to finish
    vk.WaitForFences(device, 1, &inFlightFences[currentFrame], true, bits.U64_MAX)

    // Acquire an image from the swap chain
    imageIndex: u32
    result := vk.AcquireNextImageKHR(device, swapChain, bits.U64_MAX, imageAvailableSemaphores[currentFrame], {}, &imageIndex)
    if result == .ERROR_OUT_OF_DATE_KHR {
        recreateSwapChain()
        return
    } else if result != .SUCCESS && result != .SUBOPTIMAL_KHR {
        fmt.eprintln("Failed to acquire swap chain image")
    }

    // Reset the fence to unsignaled state
    vk.ResetFences(device, 1, &inFlightFences[currentFrame])

    // Reset and record the command buffer
    vk.ResetCommandBuffer(commandBuffers[currentFrame], vk.CommandBufferResetFlags{})
    recordCommandBuffer(commandBuffers[currentFrame], imageIndex)

    // Submit the command buffer
    submitInfo: vk.SubmitInfo = {
        sType= vk.StructureType.SUBMIT_INFO,
    }

    waitSemaphores: []vk.Semaphore = {imageAvailableSemaphores[currentFrame]}
    waitStages: []vk.PipelineStageFlags = {vk.PipelineStageFlags{.COLOR_ATTACHMENT_OUTPUT}}
    submitInfo.waitSemaphoreCount = 1
    submitInfo.pWaitSemaphores = raw_data(waitSemaphores)
    submitInfo.pWaitDstStageMask = raw_data(waitStages)
    submitInfo.commandBufferCount = 1
    submitInfo.pCommandBuffers = &commandBuffers[currentFrame]

    signalSemaphores: []vk.Semaphore = {renderFinishedSemaphores[currentFrame]}
    submitInfo.signalSemaphoreCount = 1
    submitInfo.pSignalSemaphores = raw_data(signalSemaphores)

    if vk.QueueSubmit(graphicsQueue, 1, &submitInfo, inFlightFences[currentFrame]) != vk.Result.SUCCESS {
        fmt.eprintln("Failed to submit draw command buffer")
    }

    // Present the image to the swap chain
    presentInfo: vk.PresentInfoKHR = {
        sType=              vk.StructureType.PRESENT_INFO_KHR,
        waitSemaphoreCount= 1,
        pWaitSemaphores=    raw_data(signalSemaphores),
        swapchainCount=     1,
        pSwapchains=        &swapChain,
        pImageIndices=      &imageIndex,
        pResults=           nil,
    }

    result = vk.QueuePresentKHR(presentQueue, &presentInfo)
    if result == .ERROR_OUT_OF_DATE_KHR || result == .SUBOPTIMAL_KHR || framebufferResized {
        framebufferResized = false
        recreateSwapChain()
    } else if result != .SUCCESS {
        fmt.eprintln("Failed to present swap chain image")
    }

    // Advance to the next frame
    currentFrame = (currentFrame + 1) % MAX_FRAMES_IN_FLIGHT
}

// Recreates the swap chain when it's out of date
recreateSwapChain :: proc() {
    width, height := glfw.GetFramebufferSize(window)
    for width == 0 || height == 0 {
        if glfw.WindowShouldClose(window) {
            return
        }
        width, height = glfw.GetFramebufferSize(window)
        glfw.WaitEvents()
    }

    vk.DeviceWaitIdle(device)

    cleanupSwapChain()

    createSwapChain()
    createImageViews()
    createFrameBuffers()
}

/* -----------------------
   Cleanup Functions
   ----------------------- */

// Cleans up all Vulkan and GLFW resources
cleanup :: proc() {
    cleanupSwapChain()

    vk.DestroyPipeline(device, graphicsPipeline, nil)
    vk.DestroyPipelineLayout(device, pipelineLayout, nil)
    vk.DestroyRenderPass(device, renderPass, nil)

    for i := 0; i < MAX_FRAMES_IN_FLIGHT; i += 1 {
        vk.DestroySemaphore(device, renderFinishedSemaphores[i], nil)
        vk.DestroySemaphore(device, imageAvailableSemaphores[i], nil)
        vk.DestroyFence(device, inFlightFences[i], nil)
    }

    vk.DestroyCommandPool(device, commandPool, nil)

    vk.DestroyDevice(device, nil)
    when VK_DEBUG {
        vk.DestroyDebugUtilsMessengerEXT(instance, debugMessenger, nil)
    }

    vk.DestroySurfaceKHR(instance, surface, nil)
    vk.DestroyInstance(instance, nil)

    glfw.DestroyWindow(window)
    glfw.Terminate()
}

// Cleans up the swap chain resources
cleanupSwapChain :: proc() {
    for &framebuffer in swapChainFrameBuffers {
        vk.DestroyFramebuffer(device, framebuffer, nil)
    }
    for &imageView in swapChainImageViews {
        vk.DestroyImageView(device, imageView, nil)
    }
    vk.DestroySwapchainKHR(device, swapChain, nil)
}

/* -----------------------
   GLFW Error Callback
   ----------------------- */

// Handles GLFW errors by printing them to stderr
glfwErrorCallback :: proc(error: i32, description: cstring) {
    fmt.eprintln("GLFW Error: ", description)
}
