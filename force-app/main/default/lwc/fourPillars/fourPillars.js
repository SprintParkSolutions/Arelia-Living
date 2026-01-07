import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

// static resources
import ARELIA_LIVING from '@salesforce/resourceUrl/ResidentialImage';
import ARELIA_WORK from '@salesforce/resourceUrl/CommercialImage';
import ARELIA_HOSPITALITY from '@salesforce/resourceUrl/HospitalityImage';
import ARELIA_RETAIL from '@salesforce/resourceUrl/HealthcareImage';

export default class FourPillars extends NavigationMixin(LightningElement) {
    pillars = [
        {
            id: 1,
            key: 'residential',
            subtitle: '01 — LIVING',
            title: 'Bespoke Residential',
            description: 'Your home is your sanctuary. We craft personal narratives through texture, light, and form, creating spaces that are as functional as they are beautiful.',
            image: ARELIA_LIVING
        },
        {
            id: 2,
            key: 'commercial',
            subtitle: '02 — WORKSPACE',
            title: 'Commercial Innovation',
            description: 'Redefining the modern workspace. We design environments that foster creativity and collaboration, blending corporate identity with human-centric comfort.',
            image: ARELIA_WORK
        },
        {
            id: 3,
            key: 'hospitality',
            subtitle: '03 — HOSPITALITY',
            title: 'Luxury Hospitality',
            description: 'Creating unforgettable guest experiences. From boutique hotels to michelin-star restaurants, we set the stage for exquisite service and ambiance.',
            image: ARELIA_HOSPITALITY
        },
        
    ];

    // PILLAR → URL MAP
    pillarUrlMap = {
        residential: 'https://sprintpark--dev4.sandbox.my.site.com/AreliaLiving/s/residential-portfolio',
        commercial:  'https://sprintpark--dev4.sandbox.my.site.com/AreliaLiving/s/commerical-portifolio',
        hospitality: 'https://sprintpark--dev4.sandbox.my.site.com/AreliaLiving/s/hospitality-portfolio',
        
    };

    // PILLAR NAMES FOR MODAL
    pillarDataMap = {
        residential: { title: 'Residential Design', tagline: 'Bespoke homes — concept to completion.' },
        commercial:  { title: 'Commercial Interiors', tagline: 'Workplaces that perform and inspire.' },
        hospitality: { title: 'Hospitality Design', tagline: 'Crafting memorable guest experiences.' },
        
    };

    _animInit = false;
    modalOpen = false;
    activePillar = null;
    activeData = { title: '', tagline: '' };

    renderedCallback() {
        if (this._animInit) return;
        this._animInit = true;

        const cards = Array.from(this.template.querySelectorAll('.pillar-card'));
        if (!cards.length) return;

        // fade-left / fade-right assignment
        cards.forEach((card, idx) => {
            card.classList.add(idx % 2 === 0 ? 'fade-left' : 'fade-right');
        });

        // Fallback for older browsers
        if (!('IntersectionObserver' in window)) {
            cards.forEach(c => c.classList.add('is-visible'));
            return;
        }

        const io = new IntersectionObserver((entries, observer) => {
            entries.forEach(entry => {
                if (entry.isIntersecting) {
                    entry.target.classList.add('is-visible');
                    observer.unobserve(entry.target);
                }
            });
        }, { rootMargin: '0px 0px -8% 0px', threshold: 0.12 });

        cards.forEach(card => io.observe(card));
    }

    openExplore(event) {
        const key = event.currentTarget.dataset.pillar;
        if (!key) return;

        this.activePillar = key;
        const d = this.pillarDataMap[key] || {};
        this.activeData = { title: d.title, tagline: d.tagline };

        this.modalOpen = true;

        setTimeout(() => {
            const modal = this.template.querySelector('.explore-modal');
            modal && modal.focus();
        }, 50);
    }

    closeExplore() {
        this.modalOpen = false;
        this.activePillar = null;
        this.activeData = { title: '', tagline: '' };
    }

    handleBackdropClick(e) {
        if (e.target.classList.contains('explore-modal-backdrop')) {
            this.closeExplore();
        }
    }

    handleKeyDown(e) {
        if (e.key === 'Escape') {
            this.closeExplore();
        }
    }

    handleModalAction(e) {
        const action = e.currentTarget.dataset.action;
        const pillar = this.activePillar;

        // SELECT correct destination URL per pillar
        const targetUrl = this.pillarUrlMap[pillar];

        switch (action) {
            case 'styles':
            case 'beforeafter':
                // → navigate to pillar portfolio page
                this[NavigationMixin.Navigate]({
                    type: 'standard__webPage',
                    attributes: { url: targetUrl }
                });
                break;

            case 'book':
                // → navigate to registration form page you provided
                this[NavigationMixin.Navigate]({
                    type: 'standard__webPage',
                    attributes: {
                        url: 'https://sprintpark--dev4.sandbox.my.site.com/AreliaLiving/s/registration-form'
                    }
                });
                break;
        }

        this.closeExplore();
    }
}