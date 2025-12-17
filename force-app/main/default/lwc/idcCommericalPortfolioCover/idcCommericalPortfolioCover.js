import { LightningElement } from 'lwc';
import COMMERCIAL_VIDEO from '@salesforce/resourceUrl/commercial_portfolio_video';
import COMMERCIAL_POSTER from '@salesforce/resourceUrl/CommericalCover';
import { NavigationMixin } from 'lightning/navigation';

export default class IdcCommercialPortfolioCover extends NavigationMixin(LightningElement) {
    coverVideo = COMMERCIAL_VIDEO;
    posterImage = COMMERCIAL_POSTER;

    // Final registration URL (absolute)
    commercialUrl = 'https://sprintpark--dev4.sandbox.my.site.com/AreliaLiving/s/registration-form';

    renderedCallback() {
        if (this._observerInitialized) return;
        this._observerInitialized = true;

        const heroEl = this.template.querySelector('[data-hero]');
        if (!heroEl) return;

        const io = new IntersectionObserver((entries) => {
            entries.forEach(entry => {
                if (entry.isIntersecting) {
                    heroEl.classList.add('in-view');
                    io.unobserve(heroEl);
                }
            });
        }, { threshold: 0.15 });

        io.observe(heroEl);
    }

    navigateToCommercialRequest() {
        // Navigate to the absolute registration URL
        this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: {
                url: this.commercialUrl
            }
        });
    }
}