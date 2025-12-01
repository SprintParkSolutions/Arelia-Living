import { LightningElement } from 'lwc';
import ABOUT_IMAGE from '@salesforce/resourceUrl/IDCaboutUsImage';

export default class IdcAboutUs extends LightningElement {
     aboutImage = ABOUT_IMAGE;
    navigateAboutUs() {
        console.log('Navigate to full About Us page');
    }
}