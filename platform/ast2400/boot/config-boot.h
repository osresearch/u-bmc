#ifndef _config_h_
#define _config_h_
#define CONFIG_RAM_START    0x40000000
#define CONFIG_RAM_SIZE     0x7000000
#define CONFIG_RAM_END      0x47000000
#define CONFIG_DTB_START    (CONFIG_RAM_END - 0x8000)
#define CONFIG_DTB_END      CONFIG_RAM_END
#endif
