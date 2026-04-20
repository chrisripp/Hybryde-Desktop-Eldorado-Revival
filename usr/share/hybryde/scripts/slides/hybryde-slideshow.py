#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Hybryde Slideshow - Présentation interactive des environnements de bureau
Modernisé pour Python 3 avec GTK 3 et WebKit2GTK
"""

import gi
import os
import sys
import subprocess

gi.require_version('Gtk', '3.0')

# Détection automatique de la version WebKit2 disponible
WEBKIT_AVAILABLE = False
WEBKIT_VERSION = None

for version in ['4.1', '4.0', '6.0']:
    try:
        gi.require_version('WebKit2', version)
        from gi.repository import WebKit2
        WEBKIT_AVAILABLE = True
        WEBKIT_VERSION = version
        print(f"✓ WebKit2 {version} détecté")
        break
    except (ValueError, ImportError):
        continue

from gi.repository import Gtk, Gdk, GdkPixbuf

if not WEBKIT_AVAILABLE:
    print("⚠️  WebKit2GTK non disponible - utilisation du navigateur externe")
    print("Pour activer le mode intégré, installez:")
    print("  sudo apt install gir1.2-webkit2-4.1")

class HybrydeSlideshow(Gtk.Window):
    def __init__(self):
        super().__init__(title="Hybryde - Découverte des environnements")
        
        # Configuration des chemins
        self.slides_dir = "/usr/share/hybryde/scripts/slides"
        
        # Liste ordonnée des slides
        self.slides = [
            "welcome.html",
            "mate.html",
            "cinnamon.html",
            "kde.html",
            "xfce.html",
            "lxde.html",
            "e17.html",
            "openbox.html",
            "qsn.html",
            "gethelp.html"
        ]
        
        self.current_slide = 0
        self.use_webkit = WEBKIT_AVAILABLE
        
        # Configuration de la fenêtre
        self.set_default_size(900, 650)
        self.set_position(Gtk.WindowPosition.CENTER)
        self.set_resizable(True)
        # Définir des limites de taille minimale
        self.set_size_request(600, 400)
        self.connect("destroy", Gtk.main_quit)
        
        # Configuration plein écran optionnelle (décommenter si souhaité)
        # self.fullscreen()
        
        # Container principal
        main_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.add(main_box)
        
        # Overlay pour superposer le fond et le contenu
        overlay = Gtk.Overlay()
        overlay.set_hexpand(True)
        overlay.set_vexpand(True)
        main_box.pack_start(overlay, True, True, 0)
        
        # Image de fond si elle existe
        background_path = os.path.join(self.slides_dir, "background.png")
        if os.path.exists(background_path):
            try:
                # Charger l'image de fond en mode scalable
                background = Gtk.Image()
                # Utiliser from_file qui permet le scaling automatique
                pixbuf = GdkPixbuf.Pixbuf.new_from_file(background_path)
                # Redimensionner l'image pour qu'elle ne soit pas trop grande
                width = pixbuf.get_width()
                height = pixbuf.get_height()
                # Limiter à 1200px de large maximum
                if width > 1200:
                    scale = 1200 / width
                    new_width = 1200
                    new_height = int(height * scale)
                    pixbuf = pixbuf.scale_simple(new_width, new_height, GdkPixbuf.InterpType.BILINEAR)
                background.set_from_pixbuf(pixbuf)
                overlay.add(background)
            except Exception as e:
                print(f"Impossible de charger le fond: {e}")
        
        if self.use_webkit:
            # Mode WebKit intégré
            from gi.repository import WebKit2
            self.webview = WebKit2.WebView()
            
            # Configuration WebView pour transparence
            self.webview.set_background_color(Gdk.RGBA(0, 0, 0, 0))
            
            # Activer les fonctionnalités web modernes
            settings = self.webview.get_settings()
            settings.set_property('enable-javascript', True)
            settings.set_property('enable-webgl', True)
            settings.set_property('enable-smooth-scrolling', True)
            
            # ScrolledWindow pour le webview
            scrolled = Gtk.ScrolledWindow()
            scrolled.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
            scrolled.set_hexpand(True)
            scrolled.set_vexpand(True)
            scrolled.add(self.webview)
            overlay.add_overlay(scrolled)
        else:
            # Mode navigateur externe - afficher un aperçu texte
            scrolled = Gtk.ScrolledWindow()
            scrolled.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
            scrolled.set_hexpand(True)
            scrolled.set_vexpand(True)
            self.textview = Gtk.TextView()
            self.textview.set_editable(False)
            self.textview.set_wrap_mode(Gtk.WrapMode.WORD)
            self.textbuffer = self.textview.get_buffer()
            
            # Style du TextView
            self.textview.override_background_color(
                Gtk.StateFlags.NORMAL,
                Gdk.RGBA(1.0, 1.0, 1.0, 0.95)
            )
            self.textview.set_left_margin(20)
            self.textview.set_right_margin(20)
            self.textview.set_top_margin(20)
            
            scrolled.add(self.textview)
            overlay.add_overlay(scrolled)
        
        # Box pour les boutons de navigation
        nav_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        nav_box.set_halign(Gtk.Align.CENTER)
        nav_box.set_valign(Gtk.Align.END)
        nav_box.set_margin_bottom(20)
        nav_box.set_spacing(20)
        
        # Style CSS pour les boutons
        css_provider = Gtk.CssProvider()
        css_provider.load_from_data(b"""
            .nav-button {
                background: rgba(255, 255, 255, 0.9);
                border: 2px solid #333;
                border-radius: 8px;
                font-size: 24px;
                font-weight: bold;
                padding: 10px 20px;
                min-width: 60px;
                min-height: 60px;
            }
            .nav-button:hover {
                background: rgba(255, 255, 255, 1.0);
                border-color: #0066cc;
            }
            .slide-counter {
                background: rgba(0, 0, 0, 0.7);
                color: white;
                border-radius: 6px;
                padding: 8px 16px;
                font-size: 14px;
                font-weight: bold;
            }
        """)
        
        screen = Gdk.Screen.get_default()
        style_context = Gtk.StyleContext()
        style_context.add_provider_for_screen(
            screen,
            css_provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )
        
        # Bouton précédent
        self.btn_prev = Gtk.Button(label="◄")
        self.btn_prev.get_style_context().add_class("nav-button")
        self.btn_prev.connect("clicked", self.on_prev_clicked)
        nav_box.pack_start(self.btn_prev, False, False, 0)
        
        # Compteur de slides
        self.slide_counter = Gtk.Label()
        self.slide_counter.get_style_context().add_class("slide-counter")
        nav_box.pack_start(self.slide_counter, False, False, 0)
        
        # Bouton suivant
        self.btn_next = Gtk.Button(label="►")
        self.btn_next.get_style_context().add_class("nav-button")
        self.btn_next.connect("clicked", self.on_next_clicked)
        nav_box.pack_start(self.btn_next, False, False, 0)
        
        overlay.add_overlay(nav_box)
        
        # Support des touches clavier
        self.connect("key-press-event", self.on_key_press)
        
        # Charger la première slide
        self.load_slide()
        
        # Afficher tout
        self.show_all()
    
    def load_slide(self):
        """Charge la slide courante dans le WebView ou ouvre dans le navigateur"""
        slide_file = self.slides[self.current_slide]
        slide_path = os.path.join(self.slides_dir, slide_file)
        
        if not os.path.exists(slide_path):
            print(f"Slide non trouvée: {slide_path}")
            return
        
        if self.use_webkit:
            # Mode WebKit intégré
            # Lire le contenu HTML
            with open(slide_path, 'r', encoding='utf-8') as f:
                html_content = f.read()
            
            # Créer une page HTML complète avec CSS intégré
            full_html = f"""
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <style>
        body {{
            margin: 0;
            padding: 20px;
            font-family: 'Ubuntu', 'Cantarell', sans-serif;
            background: transparent;
            color: #333;
        }}
        .header {{
            text-align: center;
            margin-bottom: 20px;
        }}
        .slidetitle {{
            font-size: 2.5em;
            color: #0066cc;
            text-shadow: 2px 2px 4px rgba(0,0,0,0.3);
        }}
        .main {{
            display: flex;
            justify-content: space-between;
            align-items: flex-start;
            max-width: 1200px;
            margin: 0 auto;
            background: rgba(255, 255, 255, 0.95);
            padding: 30px;
            border-radius: 15px;
            box-shadow: 0 4px 20px rgba(0,0,0,0.2);
        }}
        .text {{
            flex: 1;
            padding-right: 30px;
        }}
        .text p {{
            font-size: 1.1em;
            line-height: 1.6;
            margin-bottom: 15px;
        }}
        .featured {{
            background: #f0f8ff;
            border-left: 4px solid #0066cc;
            padding: 15px;
            margin-top: 20px;
        }}
        .featured ul {{
            list-style: none;
            padding: 0;
            margin: 0;
        }}
        .featured li {{
            padding: 8px 0;
        }}
        .caption {{
            font-size: 1em;
            color: #555;
        }}
        .screenshot {{
            max-width: 450px;
            border: 3px solid #ddd;
            border-radius: 8px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.2);
        }}
        .screenshot2 {{
            position: fixed;
            bottom: 100px;
            right: 30px;
            width: 80px;
            height: 80px;
        }}
        .screenshot3 {{
            position: fixed;
            bottom: 20px;
            right: 30px;
            width: 60px;
            height: 60px;
            opacity: 0.8;
        }}
        b {{
            color: #0066cc;
        }}
    </style>
</head>
<body>
    {html_content}
</body>
</html>
"""
            
            # Charger le HTML avec l'URI de base pour les images relatives
            base_uri = f"file://{self.slides_dir}/"
            self.webview.load_html(full_html, base_uri)
        else:
            # Mode navigateur externe - ouvrir avec xdg-open
            try:
                subprocess.Popen(['xdg-open', slide_path])
            except Exception as e:
                print(f"Impossible d'ouvrir le navigateur: {e}")
            
            # Afficher un aperçu texte dans la fenêtre
            with open(slide_path, 'r', encoding='utf-8') as f:
                content = f.read()
            
            # Extraire le titre et un aperçu
            import re
            title_match = re.search(r'<h1[^>]*>(.*?)</h1>', content, re.IGNORECASE)
            title = title_match.group(1) if title_match else slide_file
            
            # Nettoyer les balises HTML pour l'aperçu
            text_preview = re.sub(r'<[^>]+>', '', content)
            text_preview = re.sub(r'\s+', ' ', text_preview).strip()
            
            # Créer le texte formaté
            formatted_text = f"""
╔══════════════════════════════════════════════════════════════╗
║  HYBRYDE SLIDESHOW - MODE APERÇU                            ║
╚══════════════════════════════════════════════════════════════╝

📄 Slide {self.current_slide + 1}/{len(self.slides)}: {slide_file}

📌 TITRE: {title}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

{text_preview[:500]}...

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

💡 La page complète s'ouvre dans votre navigateur par défaut.

ℹ️  Pour le mode intégré, installez WebKit2GTK:
   sudo apt install gir1.2-webkit2-4.1

📖 Utilisez les flèches pour naviguer entre les slides.
"""
            
            self.textbuffer.set_text(formatted_text)
        
        # Mettre à jour le compteur
        self.update_counter()
        
        # Mettre à jour l'état des boutons
        self.btn_prev.set_sensitive(self.current_slide > 0)
        self.btn_next.set_sensitive(self.current_slide < len(self.slides) - 1)
    
    def update_counter(self):
        """Met à jour le compteur de slides"""
        text = f"{self.current_slide + 1} / {len(self.slides)}"
        self.slide_counter.set_text(text)
    
    def on_prev_clicked(self, button):
        """Slide précédente"""
        if self.current_slide > 0:
            self.current_slide -= 1
            self.load_slide()
    
    def on_next_clicked(self, button):
        """Slide suivante"""
        if self.current_slide < len(self.slides) - 1:
            self.current_slide += 1
            self.load_slide()
    
    def on_key_press(self, widget, event):
        """Gestion des touches clavier"""
        key = event.keyval
        
        # Flèches gauche/droite ou Page Up/Down
        if key in (Gdk.KEY_Left, Gdk.KEY_Page_Up):
            self.on_prev_clicked(None)
        elif key in (Gdk.KEY_Right, Gdk.KEY_Page_Down, Gdk.KEY_space):
            self.on_next_clicked(None)
        # Échap pour quitter
        elif key == Gdk.KEY_Escape:
            Gtk.main_quit()
        # F11 pour basculer plein écran
        elif key == Gdk.KEY_F11:
            if self.get_window().get_state() & Gdk.WindowState.FULLSCREEN:
                self.unfullscreen()
            else:
                self.fullscreen()

def main():
    """Point d'entrée principal"""
    # Vérifier que le répertoire des slides existe
    slides_dir = "/usr/share/hybryde/scripts/slides"
    if not os.path.exists(slides_dir):
        print(f"Erreur: Le répertoire {slides_dir} n'existe pas!")
        print("Utilisation du répertoire courant pour les tests...")
        # Pour les tests, on pourrait utiliser un autre chemin
    
    app = HybrydeSlideshow()
    Gtk.main()

if __name__ == "__main__":
    main()
