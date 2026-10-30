/**
 * @description       :
 * @author            : donghyun.kim2@cj.net.partial
 * @group             :
 * @last modified on  : 2026-10-30
 * @last modified by  : donghyun.kim2@cj.net.partial
**/
import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import getCaseIdFromToken from '@salesforce/apex/Oy_caseFileUploadController.getCaseIdFromToken';
import checkCaseSession from '@salesforce/apex/Oy_caseFileUploadController.checkCaseSession';
import uploadFile from '@salesforce/apex/Oy_caseFileUploadController.uploadFile';
import syncOfflineVocFiles from '@salesforce/apex/Oy_caseFileUploadController.syncOfflineVocFiles';

const MAX_FILE_COUNT = 3;
const MAX_FILE_SIZE = 3 * 1024 * 1024; // 원본 파일 기준 3MB
const ACCEPTED_EXTENSIONS = ['.png', '.jpg', '.jpeg'];

// EXIF 제거용 재인코딩 설정
// - canvas 로 다시 그리면 EXIF(GPS 위치, 촬영기기, 촬영일시 등) 메타데이터가 전부 제거됨
// - Apex 호출 payload(약 4MB) / heap 한도를 넘지 않도록 리사이즈 + JPEG 압축
const MAX_DIMENSION = 2048;           // 긴 변 최대 px
const INITIAL_QUALITY = 0.85;         // JPEG 초기 품질
const MIN_QUALITY = 0.5;              // 품질 하한 (이하로는 해상도를 줄임)
const MAX_BASE64_LENGTH_PER_FILE = 700000; // 파일당 base64 약 700KB (3개 합산 약 2MB, guest heap 6MB 고려)

export default class Oy_caseFileUploadForm extends NavigationMixin(LightningElement) {
    @track myRecordId;
    @track fileUploaded = false;
    token;
    webKey;
    showInlineMessage = false;
    inlineMessage = '';
    isInputDisabled = false;
    isLoading = false;

    connectedCallback(){
        console.log('connectedCallback');
        // URL 파라미터에서 token 값 읽기
        const urlParams = new URLSearchParams(window.location.search);
        this.token = urlParams.get('token');
        this.webKey = urlParams.get('webKey');

        let urlToCheck = window.location.hostname;
        console.log('urlToCheck :::', urlToCheck);

        if(urlToCheck.includes('builder') || urlToCheck.includes('preview')){
            console.log('builder url');
        } else {
            getCaseIdFromToken({ encodedToken: this.token }).then(result => {
                console.log('result :::', JSON.stringify(result, null, 2));
                if (result && result.status === 'S' && result.caseId) {
                    this.myRecordId = result.caseId;
                    console.log('myRecordId :::', this.myRecordId);
                    return checkCaseSession({ caseId: this.myRecordId, webKey: this.webKey });

                } else {
                    // 오류 발생 시 /error 페이지로 리다이렉트
                    this.navigateToErrorPage();
                    return null;
                }
            }).then(isCompleted => {
                if (isCompleted === true) {
                    this.isInputDisabled = true;
                    this.inlineMessage = '이미 파일 첨부가 완료된 URL입니다.';
                    this.showInlineMessage = true;
                }
            }).catch(error => {
                console.log('error :::', error);
                // 예외 발생 시 /error 페이지로 리다이렉트
                this.navigateToErrorPage();
            });
        }
    }

    get acceptedFormats() {
        return ACCEPTED_EXTENSIONS.join(',');
    }

    isAcceptedFile(fileName) {
        if (!fileName || typeof fileName !== 'string') return false;
        const lowerName = fileName.toLowerCase();
        return ACCEPTED_EXTENSIONS.some((ext) => lowerName.endsWith(ext));
    }

    async handleFileChange(event) {
        const fileInputElement = event.target;
        const files = Array.from(fileInputElement.files || []);
        if (files.length === 0) return;

        if (files.length > MAX_FILE_COUNT) {
            this.showToast('', `최대 ${MAX_FILE_COUNT}개의 파일만 업로드할 수 있습니다.`, 'warning');
            fileInputElement.value = '';
            return;
        }

        const invalidFiles = files.filter((file) => !this.isAcceptedFile(file.name));
        if (invalidFiles.length > 0) {
            const fileNames = invalidFiles.map((f) => f.name).join(', ');
            this.showToast('', `허용되지 않는 파일 형식입니다. (PNG, JPG, JPEG만 가능) - ${fileNames}`, 'warning');
            fileInputElement.value = '';
            return;
        }

        const oversizedFiles = files.filter((file) => file.size > MAX_FILE_SIZE);
        if (oversizedFiles.length > 0) {
            const fileNames = oversizedFiles.map((f) => f.name).join(', ');
            this.showToast('', `파일 크기가 3MB를 초과할 수 없습니다. (${fileNames})`, 'warning');
            fileInputElement.value = '';
            return;
        }

        this.isLoading = true;
        this.isInputDisabled = true;
        try {
            // 각 파일의 EXIF(위치정보 등) 제거 후 base64 변환
            const fileMap = {};
            for (const file of files) {
                const stripped = await this.stripExif(file);
                fileMap[this.uniqueFileName(fileMap, stripped.name)] = stripped.content;
            }

            // uploadFile 에서 webKey__c 까지 저장하므로 updateContentVersionWebKey 호출 불필요
            const result = await uploadFile({ caseId: this.myRecordId, webKey: this.webKey, fileMap: fileMap });
            console.log('uploadFile result :::', JSON.stringify(result, null, 2));
            if (result && result.status === 'S') {
                // 오프라인 VOC 파일 동기화 요청 (실패해도 업로드는 완료 처리)
                const syncResult = await syncOfflineVocFiles({ caseId: this.myRecordId, contentVersionIdList: result.contentVersionIdList });
                console.log('syncResult :::', JSON.stringify(syncResult, null, 2));

                this.fileUploaded = true;
                this.showToast('File(s) Upload', '파일 업로드 성공', 'success');
            } else if (result && result.status === 'W') {
                this.isInputDisabled = false;
                this.showToast('File(s) Upload', result.message, 'warning');
            } else {
                this.isInputDisabled = false;
                this.showToast('File(s) Upload', '파일 업로드 실패', 'error');
            }
        } catch (error) {
            console.error('업로드 오류:', error);
            this.isInputDisabled = false;
            this.showToast('File(s) Upload', '파일 읽기 또는 업로드 중 오류가 발생했습니다.', 'error');
        } finally {
            this.isLoading = false;
            fileInputElement.value = '';
        }
    }

    /**
     * 이미지를 canvas 에 다시 그려 JPEG 로 재인코딩한다.
     * - canvas 출력물에는 EXIF/XMP 등 메타데이터가 포함되지 않으므로 GPS 위치정보가 제거됨
     * - 브라우저가 img 를 그릴 때 EXIF Orientation 을 적용하므로 회전 상태는 픽셀에 반영되어 유지됨
     * - PNG 도 tEXt/eXIf 청크에 메타데이터가 있을 수 있어 동일하게 처리 (투명 영역은 흰색 배경)
     * @returns {Promise<{name: string, content: string}>} content 는 순수 base64 문자열
     */
    async stripExif(file) {
        const dataUrl = await this.readAsDataUrl(file);
        const image = await this.loadImage(dataUrl);

        let maxDimension = MAX_DIMENSION;
        let quality = INITIAL_QUALITY;
        let base64 = this.renderToJpegBase64(image, maxDimension, quality);

        // 용량이 크면 품질 → 해상도 순으로 낮춰 재시도
        while (base64.length > MAX_BASE64_LENGTH_PER_FILE && maxDimension > 640) {
            if (quality > MIN_QUALITY) {
                quality = Math.max(MIN_QUALITY, quality - 0.1);
            } else {
                maxDimension = Math.round(maxDimension * 0.8);
            }
            base64 = this.renderToJpegBase64(image, maxDimension, quality);
        }

        const baseName = file.name.replace(/\.[^.]+$/, '');
        return { name: `${baseName}.jpg`, content: base64 };
    }

    renderToJpegBase64(image, maxDimension, quality) {
        const width = image.naturalWidth || image.width;
        const height = image.naturalHeight || image.height;
        const scale = Math.min(1, maxDimension / Math.max(width, height));

        const canvas = document.createElement('canvas');
        canvas.width = Math.round(width * scale);
        canvas.height = Math.round(height * scale);

        const ctx = canvas.getContext('2d');
        ctx.fillStyle = '#ffffff';
        ctx.fillRect(0, 0, canvas.width, canvas.height);
        ctx.drawImage(image, 0, 0, canvas.width, canvas.height);

        return canvas.toDataURL('image/jpeg', quality).split(',')[1];
    }

    readAsDataUrl(file) {
        return new Promise((resolve, reject) => {
            const reader = new FileReader();
            reader.onload = () => resolve(reader.result);
            reader.onerror = () => reject(reader.error);
            reader.readAsDataURL(file);
        });
    }

    loadImage(src) {
        return new Promise((resolve, reject) => {
            const image = new Image();
            image.onload = () => resolve(image);
            image.onerror = () => reject(new Error('이미지를 불러올 수 없습니다.'));
            image.src = src;
        });
    }

    // a.png, a.jpg 처럼 확장자만 다른 파일이 모두 a.jpg 가 되어 덮어써지는 것 방지
    uniqueFileName(fileMap, name) {
        if (!(name in fileMap)) return name;
        const baseName = name.replace(/\.jpg$/, '');
        let index = 1;
        while (`${baseName}(${index}).jpg` in fileMap) index++;
        return `${baseName}(${index}).jpg`;
    }

    showToast(title, message, variant) {
        const evt = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant,
            mode: 'dismissable'
        });
        this.dispatchEvent(evt);
    }

    navigateToErrorPage() {
        console.log('navigateToErrorPage');

        this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: {
                url: '/error'
            }
        });
    }
}
