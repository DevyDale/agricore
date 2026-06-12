// i18n.js: Global translation and currency formatting utility

(function(global) {
    // Translation dictionaries (expand as needed)
    const translations = {
        en: {},
        fr: { 'Professional Network': 'Réseau professionnel', 'Connect with skilled professionals to power your farm work': 'Connectez-vous avec des professionnels qualifiés pour dynamiser votre ferme', 'All': 'Tous', 'Agronomists': 'Agronomes', 'Veterinarians': 'Vétérinaires', 'Mechanics': 'Mécaniciens', 'Farm Managers': 'Gestionnaires de ferme', 'Livestock Handlers': 'Manieurs de bétail', 'Minimum Rating': 'Note minimale', 'Max Hourly Rate ($)': 'Taux horaire max (€)', 'Min Experience (years)': 'Expérience min (années)', 'Availability': 'Disponibilité', 'Any Rating': 'Toute note', 'Available Now': 'Disponible maintenant', 'Full-Time': 'Temps plein', 'Part-Time': 'Temps partiel', 'Contract': 'Contrat', 'Highest Rated': 'Mieux noté', 'Lowest Rate': 'Taux le plus bas', 'Highest Rate': 'Taux le plus élevé', 'Most Experienced': 'Le plus expérimenté', 'Newest': 'Le plus récent', 'Professionals Available': 'Professionnels disponibles', 'No professionals found': 'Aucun professionnel trouvé', 'Try adjusting your filters': 'Essayez de modifier vos filtres', 'View Profile': 'Voir le profil', 'Chat with Professional': 'Discuter', 'Leave Review': 'Laisser un avis', 'Location:': 'Lieu :', 'Experience:': 'Expérience :', 'Rate:': 'Tarif :', 'Availability:': 'Disponibilité :', 'About': 'À propos', 'Skills': 'Compétences', 'Opening chat...': 'Ouverture du chat...', 'Review feature coming soon!': 'Fonction d’avis bientôt disponible !' },
        // Add more languages here
    };

    // Supported currencies and locales
    const currencyLocales = {
        USD: 'en-US',
        EUR: 'fr-FR',
        NGN: 'en-NG',
        KES: 'en-KE',
        ZAR: 'en-ZA',
        // Add more as needed
    };

    // Get user preferences
    function getUserLanguage() {
        return localStorage.getItem('preferred_language') || 'en';
    }
    function getUserCurrency() {
        return localStorage.getItem('preferred_currency') || 'USD';
    }

    // Translation function
    function t(key) {
        const lang = getUserLanguage();
        if (translations[lang] && translations[lang][key]) return translations[lang][key];
        return key;
    }

    // Currency formatting function
    function formatCurrency(amount) {
        const curr = getUserCurrency();
        const locale = currencyLocales[curr] || 'en-US';
        try {
            return new Intl.NumberFormat(locale, { style: 'currency', currency: curr }).format(amount);
        } catch {
            return `${curr} ${amount}`;
        }
    }

    // Expose globally
    global.i18n = { t, formatCurrency, getUserLanguage, getUserCurrency };
})(window);