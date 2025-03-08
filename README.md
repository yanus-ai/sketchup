# Yanus AI - Sketchup Connector

---

**Description:**  
The repository contains the **Yanus AI - Sketchup Extension**, a SketchUp plugin designed to capture masks and send them to the Yanus API.

**Core Plugin Classes**

1. **Color Profile Class**  
   Manages the replacement, generation, restoration, and deletion of materials.  
   *File: `colorprofile.rb`*

2. **Dialogs Class**  
   Controls HTML dialogs and the user interface components.  
   *File: `dialogs.rb`*

3. **Web Connection Class**  
   Oversees API interactions including establishing connections and handling responses.  
   *File: `web_connect.rb`*

4. **Menu Class**  
   Integrates toolbar actions and SketchUp menu access.  
   *File: `menu.rb`*

---

**Main Injection File:**  
`main.rb`  
Responsible for initializing the plugin, managing scene settings, image capture, JSON conversion, and additional core functions.


**Setup & Installation**

1. **Download the Plugin RBZ File:**  
   Ensure you have the latest `.rbz` file for the Yanus AI - Sketchup Connector plugin.

2. **Install the Plugin:**  
   Open SketchUp and go to **Window > Extension Manager**.  
   Click **Install Extension** and select the downloaded `.rbz` file.  