#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
About Hybryde - Version modernisée pour Python 3
Affiche les informations et slides de présentation d'Hybryde Desktop
"""

import gi
import sys
import os

gi.require_version('Gtk', '3.0')

# Essayer différentes versions de WebKit2GTK
WEBKIT_VERSION = None
for version in ['4.1', '6.0', '4.0']:
    try:
        gi.require_version('WebKit2', version)
        from gi.repository import WebKit2
        WEBKIT_VERSION = version
        break
    except (ValueError, ImportError):
        continue

if WEBKIT_VERSION is None:
    print("Erreur: WebKit2GTK n'est pas installé.")
    print("\nPour installer, exécutez:")
    print("  sudo apt install gir1.2-webkit2-4.1")
    print("  ou")
    print("  sudo apt install gir1.2-webkit-6.0")
    sys.exit(1)

from gi.repository import Gtk

class AboutHybryde:
    def __init__(self, html_file=None):
        # Déterminer le chemin du fichier HTML
        if html_file is None:
            # Chercher le fichier index.html dans plusieurs emplacements
            possible_paths = [
                '/usr/share/hybryde/scripts/slides/index.html',
                '/usr/share/hybryde/slides/index.html',
                os.path.join(os.path.dirname(__file__), 'index.html'),
                'index.html'
            ]
            
            html_file = None
            for path in possible_paths:
                if os.path.exists(path):
                    html_file = path
                    break
            
            if html_file is None:
                print("Erreur: Impossible de trouver le fichier index.html")
                print(f"Chemins recherchés: {possible_paths}")
                sys.exit(1)
        
        self.html_file = html_file
        
        # Essayer de charger le fichier Glade si disponible
        glade_file = None
        glade_paths = [
            '/usr/share/hybryde/scripts/slides/about-hybryde.glade',
            '/usr/share/hybryde/about-hybryde.glade',
            os.path.join(os.path.dirname(__file__), 'about-hybryde.glade'),
            'about-hybryde.glade'
        ]
        
        for path in glade_paths:
            if os.path.exists(path):
                glade_file = path
                break
        
        if glade_file:
            self.build_from_glade(glade_file)
        else:
            self.build_interface()
        
        self.window.connect("destroy", Gtk.main_quit)
        self.window.show_all()
    
    def build_from_glade(self, glade_file):
        """Construire l'interface depuis le fichier Glade"""
        builder = Gtk.Builder()
        try:
            builder.add_from_file(glade_file)
            builder.connect_signals(self)
            
            self.window = builder.get_object("window1")
            frame = builder.get_object("frame1")
            
            # Créer le widget WebKit2
            self.webview = WebKit2.WebView()
            self.webview.set_size_request(870, 480)
            
            # Ajouter le webview au frame
            frame.add(self.webview)
            
            # Charger le fichier HTML
            html_uri = f"file://{os.path.abspath(self.html_file)}"
            self.webview.load_uri(html_uri)
            
        except Exception as e:
            print(f"Erreur lors du chargement du fichier Glade: {e}")
            print("Construction de l'interface manuellement...")
            self.build_interface()
    
    def build_interface(self):
        """Construire l'interface manuellement si le Glade n'est pas disponible"""
        # Créer la fenêtre principale
        self.window = Gtk.Window()
        self.window.set_title("À propos d'Hybryde")
        self.window.set_default_size(1280, 760)
        self.window.set_position(Gtk.WindowPosition.CENTER)
        self.window.set_resizable(True)
        
        # Créer le conteneur vertical principal
        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.window.add(vbox)
        
        # Créer le frame pour le contenu web
        frame = Gtk.Frame()
        frame.set_size_request(1215, 670)
        frame.set_shadow_type(Gtk.ShadowType.NONE)
        
        # Créer une boîte de défilement pour le webview
        scrolled = Gtk.ScrolledWindow()
        scrolled.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
        
        # Créer le widget WebKit2
        self.webview = WebKit2.WebView()
        scrolled.add(self.webview)
        frame.add(scrolled)
        
        vbox.pack_start(frame, True, True, 0)
        
        # Créer la barre de boutons en bas
        hbox = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        hbox.set_size_request(-1, 40)
        
        # Bouton Quitter
        button = Gtk.Button(label="Quitter")
        button.set_size_request(100, 30)
        button.connect("clicked", self.on_button1_clicked)
        hbox.pack_end(button, False, False, 20)
        
        vbox.pack_start(hbox, False, False, 5)
        
        # Charger le fichier HTML
        html_uri = f"file://{os.path.abspath(self.html_file)}"
        self.webview.load_uri(html_uri)
    
    def on_button1_clicked(self, widget):
        """Gestionnaire du bouton Quitter"""
        Gtk.main_quit()

def main():
    """Point d'entrée principal"""
    html_file = None
    
    # Vérifier si un fichier HTML est passé en argument
    if len(sys.argv) > 1:
        html_file = sys.argv[1]
        if not os.path.exists(html_file):
            print(f"Erreur: Le fichier {html_file} n'existe pas")
            sys.exit(1)
    
    # Créer et lancer l'application
    AboutHybryde(html_file)
    Gtk.main()

if __name__ == "__main__":
    main()
