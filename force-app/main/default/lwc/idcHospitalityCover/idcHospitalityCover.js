import { LightningElement } from 'lwc';
import COVER_VIDEO from '@salesforce/resourceUrl/hospitality_portfolio_video';
import COVER_POSTER from '@salesforce/resourceUrl/HospitalityCover';
import { NavigationMixin } from 'lightning/navigation';
export default class IdcHospitalityCover extends NavigationMixin(LightningElement) {
   coverVideo = COVER_VIDEO;
    posterImage = COVER_POSTER;

    hospitalityUrl = 'https://sprintpark--dev4.sandbox.my.site.com/AreliaLiving/s/registration-form';

    renderedCallback() {
        if (this._observerInitialized) return;
        this._observerInitialized = true;

        const heroEl = this.template.querySelector('[data-hero]');
        if (!heroEl) return;

        const io = new IntersectionObserver((entries) => {
            entries.forEach((entry) => {
                if (entry.isIntersecting) {
                    heroEl.classList.add('in-view');
                    io.unobserve(heroEl);
                }
            });
        }, { threshold: 0.15 });

        io.observe(heroEl);
    }

    navigateToProjectRequest() {
        this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: { url: this.hospitalityUrl }
        });
    }
}