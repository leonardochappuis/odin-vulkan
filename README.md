# odin-vulkan

This repo follows the [Vulkan Tutorial](https://vulkan-tutorial.com/) in Odin.
The `main.odin` file goes up to the ["Swap Chain Recreation"](https://vulkan-tutorial.com/Drawing_a_triangle/Swap_chain_recreation) module.

## Running
From the root folder, run:
```bash
odin run main
```

## Compiling
From the root folder, run:
```bash
odin build main -out:triangle
```

Make sure the folder structure looks like:
```plaintext
triangle
main/
    └── main.odin
    └── shaders/
        ├── simple_frag.spv
        └── simple_vertex.spv
    
```

Then, you can run it with:
```bash
./triangle
```

## License
This project is licensed under the [0BSD License](LICENSE).
