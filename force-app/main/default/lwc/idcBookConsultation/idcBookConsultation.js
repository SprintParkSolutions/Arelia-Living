import { LightningElement } from 'lwc';
import appointmentImage from '@salesforce/resourceUrl/appointmentImage';
import { NavigationMixin } from 'lightning/navigation';
import Arelia_Site_Label from '@salesforce/label/c.Arelia_Site_Label';

export default class IdcBookConsultation extends NavigationMixin(LightningElement) {
    appointmentImg = appointmentImage;
    siteUrl = Arelia_Site_Label;

    handleBookClick() {
        this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: {
                url: `${this.siteUrl}registration-form`
            }
        });
    }
}